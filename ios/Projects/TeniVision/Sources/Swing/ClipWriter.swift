import AVFoundation
import CoreVideo
import Foundation

/// 프레임을 모아 `.mov` 하나로 쓴다.
///
/// ## 왜 스트리밍인가
///
/// 전체 프레임을 배열로 받으면 **클립 길이만큼 메모리를 쥐어야 한다.**
/// 겹치는 스윙은 한 클립으로 병합되므로(기획서 선택지 2) 랠리가 길면
/// 구간도 길어진다. 링 버퍼 창은 유한하니 배열로 받는 설계에서는 긴 랠리의
/// **클립 머리가 조용히 버려진다.**
///
/// 그래서 구간이 열려 있는 동안 프레임을 하나씩 쓴다. 버퍼는 `preRoll`만
/// 들고 있으면 되고, 클립 길이에 상한이 필요 없어진다.
///
/// `TeniTool`의 `VideoWriter`가 같은 이유로 같은 모양이다 — 1080p 스윕이
/// 전체 프레임 보관 때문에 메모리 부족으로 죽었다(이슈 #31).
///
/// ## 왜 H.264인가
///
/// [아키텍처 2.4](../../../../docs/02-설계/ARCHITECTURE.md)가 영상을 HEVC로
/// 적었지만 그것은 **업로드·보관** 기준이다. 시뮬레이터 인코더에서 HEVC가
/// 도는지 확인하지 못했고, 게이트가 깨지면 **검증 없이 가는 것**이 된다.
/// 전환은 실기기에서 인코딩 비용을 재고 나서다.
///
/// 근거: docs/07-기획/SPEC-0091-swing-clip-recording.md 구현 선택지 5
public struct ClipWriter: Sendable {

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case emptyClip
        case cannotReadDimensions
        case timestampWentBackwards
        case fileAlreadyExists(String)
        case writerFailed(String)

        public var description: String {
            switch self {
            case .emptyClip: "쓸 프레임이 없습니다"
            case .cannotReadDimensions: "프레임 크기를 읽을 수 없습니다"
            case .timestampWentBackwards: "프레임 시각이 역행했습니다"
            case .fileAlreadyExists(let name): "이미 있는 파일입니다: \(name)"
            case .writerFailed(let reason): "클립 기록 실패: \(reason)"
            }
        }
    }

    public struct Written: Sendable, Equatable {
        public let url: URL
        public let frameCount: Int
        /// 첫 프레임부터 마지막 프레임까지의 간격.
        public let duration: TimeInterval
        /// 첫 프레임의 **프레임 시계** 값. 영상의 PTS 0이 이 시각이다.
        /// 벽시계가 아니다 — `RecordedClip.startedAt` 참고.
        public let startedAt: TimeInterval

        public init(url: URL, frameCount: Int, duration: TimeInterval, startedAt: TimeInterval) {
            self.url = url
            self.frameCount = frameCount
            self.duration = duration
            self.startedAt = startedAt
        }
    }

    /// PTS 타임스케일. 120fps에서 한 프레임이 5틱이라 반올림 오차가
    /// 프레임 간격보다 훨씬 작다.
    static let timescale: CMTimeScale = 600

    /// 한 클립을 쓰는 동안 살아 있는 쓰기 세션.
    ///
    /// 클래스인 이유는 `AVAssetWriter`가 참조 타입이고 상태를 누적하기
    /// 때문이다. 소유자는 `ClipRecorder`(actor)이며 격리 밖으로 넘기지
    /// 않는다.
    public final class Session {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let url: URL
        private let origin: TimeInterval
        private var latest: TimeInterval
        private var count = 0

        /// 첫 프레임으로 크기를 정하고 그 시각을 PTS 0으로 삼는다.
        public init(url: URL, first: some ClipFrame) throws {
            let (width, height) = try first.withPixelBuffer { buffer -> (Int, Int) in
                let w = CVPixelBufferGetWidth(buffer)
                let h = CVPixelBufferGetHeight(buffer)
                guard w > 0, h > 0 else { throw Failure.cannotReadDimensions }
                return (w, h)
            }

            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // **덮어쓰지 않는다.** stamp는 1초 해상도이고 index는 recorder마다
            // 1부터 다시 센다 — 1초 안에 세션을 다시 시작하면 앞 세션의
            // 클립을 지우게 되고, DB의 그 행은 남의 영상을 가리킨다.
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw Failure.fileAlreadyExists(url.lastPathComponent)
            }

            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                ]
            )
            // 소급 저장이다 — 프레임은 이미 버퍼에 있고 실시간 공급이 아니다.
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: nil
            )
            guard writer.canAdd(input) else {
                throw Failure.writerFailed("입력을 추가할 수 없습니다")
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "startWriting")
            }
            writer.startSession(atSourceTime: .zero)

            self.url = url
            self.origin = first.seconds
            self.latest = first.seconds
        }

        public var frameCount: Int { count }

        /// - Note: 시각이 역행하면 `AVAssetWriter`가 append를 거부한다.
        ///   조용히 넘기지 않고 오류로 올린다.
        public func append(_ frame: some ClipFrame) throws {
            // `latest`는 첫 프레임 시각으로 초기화된다. 그래서 `count == 0`
            // 예외가 필요 없고, **첫 프레임보다 이른 것을 넣으면 거부된다** —
            // 세션은 .zero에서 시작하므로 그런 프레임은 음수 PTS가 된다.
            guard frame.seconds >= latest else {
                throw Failure.timestampWentBackwards
            }
            while !input.isReadyForMoreMediaData {
                // 상태를 보지 않으면 **영원히 돌 수 있다.** writer가 .failed로
                // 떨어진 순간 isReadyForMoreMediaData가 false였다면 다시
                // true가 되지 않는다. 소유자가 actor이므로 그 스핀은
                // 협력 스레드 하나를 영구 점유하고 recorder 전체를 막는다.
                guard writer.status == .writing else {
                    throw Failure.writerFailed(
                        writer.error?.localizedDescription ?? "status=\(writer.status.rawValue)"
                    )
                }
                // 실시간이 아니므로 짧게 양보하면 충분하다.
                usleep(1000)
            }
            let time = CMTime(
                seconds: frame.seconds - origin, preferredTimescale: ClipWriter.timescale
            )
            let appended = frame.withPixelBuffer { buffer in
                adaptor.append(buffer, withPresentationTime: time)
            }
            guard appended else {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "append")
            }
            latest = frame.seconds
            count += 1
        }

        /// 쓰기를 포기하고 **덜 쓰인 파일을 지운다.**
        ///
        /// 중간에 실패한 세션을 그냥 버리면 `AVAssetWriter`가 종료되지 않아
        /// 재생할 수 없는 `.mov`가 디스크에 남는다.
        public func cancel() {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }

        /// 파일을 닫는다.
        ///
        /// `finishWriting`은 비동기다. 끝날 때까지 기다린다 — 안 기다리면
        /// **덜 쓰인 파일이 도메인에 기록된다.**
        public func finish() throws -> Written {
            guard count > 0 else { throw Failure.emptyClip }
            input.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting { semaphore.signal() }
            semaphore.wait()
            if writer.status == .failed {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "finishWriting")
            }
            return Written(
                url: url, frameCount: count, duration: latest - origin, startedAt: origin
            )
        }
    }

    public init() {}

    /// 모여 있는 프레임을 한 번에 쓴다. 생산 경로는 `Session`으로
    /// 스트리밍한다 — 이것은 길이가 정해진 입력을 쓸 때의 편의다.
    public func write(_ frames: [some ClipFrame], to url: URL) throws -> Written {
        guard let first = frames.first else { throw Failure.emptyClip }
        let session = try Session(url: url, first: first)
        do {
            for frame in frames { try session.append(frame) }
            return try session.finish()
        } catch {
            session.cancel()
            throw error
        }
    }
}
