import AVFoundation
import CoreMedia
import Foundation
import Vision

/// 영상에 `DetectTrajectoriesRequest`를 돌려 궤적을 모은다.
///
/// 설계 근거는 docs/08-레퍼런스/ml/DetectTrajectories.md에 있다. 요약하면:
///
/// - `StatefulRequest`이므로 **인스턴스를 재사용**한다. 프레임마다 새로 만들면
///   상태가 날아가 궤적이 절대 확정되지 않는다
/// - **`CMSampleBuffer`로 먹인다.** `CGImage`로 변환하면 타임스탬프가 사라져
///   `timeRange`가 nil이 된다
/// - **`uuid`로 중복을 제거한다.** 프레임마다 갱신된 관측이 나오므로
///   그대로 세면 한 타구를 여러 번 센다
public struct TrajectoryAnalyzer: Sendable {

    public enum Failure: Error, CustomStringConvertible {
        case cannotReadVideo(String)
        case noVideoTrack

        public var description: String {
            switch self {
            case .cannotReadVideo(let reason): "영상을 읽을 수 없습니다: \(reason)"
            case .noVideoTrack: "영상 트랙이 없습니다"
            }
        }
    }

    public struct Trajectory: Sendable {
        public let uuid: UUID
        public let startFrame: Int
        public let durationSec: Double
        public let movingAverageRadius: Double
        public let pointCount: Int
        public let confidence: Double
    }

    public struct VideoInfo: Sendable {
        public let fps: Double
        public let width: Int
        public let height: Int
        public let frameCount: Int
    }

    public let trajectoryLength: Int
    public let minimumRadius: Float
    public let maximumRadius: Float

    public init(trajectoryLength: Int, minimumRadius: Float, maximumRadius: Float) {
        self.trajectoryLength = trajectoryLength
        self.minimumRadius = minimumRadius
        self.maximumRadius = maximumRadius
    }

    public struct Output: Sendable {
        public let trajectories: [Trajectory]
        public let video: VideoInfo
        /// timeRange를 하나도 못 얻었는가. 얻지 못하면 startFrame이
        /// 프레임 카운터 기반 근사가 되므로 보고해야 한다.
        public let timeRangeAvailable: Bool
    }

    public func analyze(url: URL) async throws -> Output {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let fps = Double(try await track.load(.nominalFrameRate))
        let size = try await track.load(.naturalSize)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw Failure.cannotReadVideo(error.localizedDescription)
        }

        // 요청이 기대하는 픽셀 포맷으로 디코딩한다.
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw Failure.cannotReadVideo(reader.error?.localizedDescription ?? "startReading")
        }

        // ★ 인스턴스를 하나만 만들어 모든 프레임에 재사용한다.
        var request = DetectTrajectoriesRequest(trajectoryLength: trajectoryLength)
        request.objectMinimumNormalizedRadius = minimumRadius
        request.objectMaximumNormalizedRadius = maximumRadius

        var latest: [UUID: Trajectory] = [:]
        var frameIndex = 0
        var sawTimeRange = false

        while let sample = output.copyNextSampleBuffer() {
            defer { frameIndex += 1 }

            let observations = try await request.perform(on: sample, orientation: nil)
            for observation in observations {
                let start: Int
                let duration: Double
                if let range = observation.timeRange {
                    sawTimeRange = true
                    start = Int((range.start.seconds * fps).rounded())
                    duration = range.duration.seconds
                } else {
                    // timeRange가 없으면 현재 프레임에서 점 개수만큼 거슬러 올라간다.
                    // 근사이므로 timeRangeAvailable로 보고한다.
                    start = max(0, frameIndex - observation.detectedPoints.count + 1)
                    duration = Double(observation.detectedPoints.count) / max(fps, 1)
                }

                // 같은 uuid는 마지막 관측으로 덮어쓴다 — 점이 가장 많이 쌓인 상태다.
                latest[observation.uuid] = Trajectory(
                    uuid: observation.uuid,
                    startFrame: start,
                    durationSec: duration,
                    movingAverageRadius: Double(observation.movingAverageRadius),
                    pointCount: observation.detectedPoints.count,
                    confidence: Double(observation.confidence)
                )
            }
        }

        if reader.status == .failed {
            throw Failure.cannotReadVideo(reader.error?.localizedDescription ?? "reading")
        }

        return Output(
            trajectories: latest.values.sorted { $0.startFrame < $1.startFrame },
            video: VideoInfo(
                fps: fps,
                width: Int(size.width),
                height: Int(size.height),
                frameCount: frameIndex
            ),
            timeRangeAvailable: sawTimeRange
        )
    }
}
