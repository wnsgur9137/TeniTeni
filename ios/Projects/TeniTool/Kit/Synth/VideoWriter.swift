import AVFoundation
import CoreVideo
import Foundation

/// 그레이 버퍼를 받아 .mov로 쓴다.
///
/// 무압축이 아니라 H.264를 쓴다 — 실제 촬영물이 압축을 거치므로
/// 압축 열화 없는 영상으로 검증하면 낙관적 결과가 나온다.
public struct VideoWriter {

    public enum Failure: Error, CustomStringConvertible {
        case cannotCreatePixelBuffer
        case writerFailed(String)

        public var description: String {
            switch self {
            case .cannotCreatePixelBuffer: "픽셀 버퍼를 만들 수 없습니다"
            case .writerFailed(let reason): "영상 기록 실패: \(reason)"
            }
        }
    }

    public let url: URL
    public let width: Int
    public let height: Int
    public let fps: Double

    /// 프레임을 하나씩 받아 쓴다.
    ///
    /// **전체 프레임을 배열로 받지 않는다.** 1080p·120fps·6초면 756장 ×
    /// 2MB = 1.5GB가 되어 1080p 스윕이 메모리 부족으로 죽었다 (이슈 #31).
    /// 세션은 한 장만 들고 있으면 된다.
    public final class Session {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let width: Int
        private let height: Int
        private let fps: Double
        private var index = 0

        init(url: URL, width: Int, height: Int, fps: Double) throws {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            self.width = width
            self.height = height
            self.fps = fps

            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                ]
            )
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                ]
            )
            writer.add(input)
            guard writer.startWriting() else {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "startWriting")
            }
            writer.startSession(atSourceTime: .zero)
        }

        public func append(_ gray: [UInt8]) throws {
            while !input.isReadyForMoreMediaData {
                // 실시간이 아니므로 짧게 양보하면 충분하다
                usleep(1000)
            }
            let timescale: CMTimeScale = 600
            let buffer = try Self.makePixelBuffer(
                gray: gray, width: width, height: height, pool: adaptor.pixelBufferPool
            )
            let time = CMTime(
                value: CMTimeValue((Double(index) / fps * Double(timescale)).rounded()),
                timescale: timescale
            )
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "append")
            }
            index += 1
        }

        public func finish() throws {
            input.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting { semaphore.signal() }
            semaphore.wait()
            if writer.status == .failed {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "finishWriting")
            }
        }

        /// 어댑터 풀이 있으면 버퍼를 재사용한다. 프레임마다 새로 할당하면
        /// 756장에서 그것만으로 수백 MB가 오간다.
        static func makePixelBuffer(
            gray: [UInt8], width: Int, height: Int, pool: CVPixelBufferPool?
        ) throws -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            let status: CVReturn
            if let pool {
                status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            } else {
                status = CVPixelBufferCreate(
                    kCFAllocatorDefault, width, height,
                    kCVPixelFormatType_32BGRA,
                    [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
                    &buffer
                )
            }
            guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
                throw Failure.cannotCreatePixelBuffer
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                throw Failure.cannotCreatePixelBuffer
            }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let pointer = base.assumingMemoryBound(to: UInt8.self)

            for y in 0..<height {
                let row = pointer.advanced(by: y * bytesPerRow)
                for x in 0..<width {
                    let value = gray[y * width + x]
                    let offset = x * 4
                    row[offset + 0] = value  // B
                    row[offset + 1] = value  // G
                    row[offset + 2] = value  // R
                    row[offset + 3] = 255    // A
                }
            }
            return pixelBuffer
        }
    }

    public func makeSession() throws -> Session {
        try Session(url: url, width: width, height: height, fps: fps)
    }

    /// 전체 프레임을 받는 편의 메서드. **테스트용이다** — 생산 경로는
    /// `makeSession()`으로 스트리밍한다.
    public func write(frames: [[UInt8]]) throws {
        let session = try makeSession()
        for frame in frames { try session.append(frame) }
        try session.finish()
    }

}
