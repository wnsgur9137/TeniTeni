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

    /// `frames`는 프레임 인덱스 순서의 그레이 버퍼(width*height)다.
    public func write(frames: [[UInt8]]) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
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

        let timescale: CMTimeScale = 600
        for (index, gray) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                // 실시간이 아니므로 짧게 양보하면 충분하다
                usleep(1000)
            }
            let buffer = try makePixelBuffer(gray: gray)
            let time = CMTime(
                value: CMTimeValue((Double(index) / fps * Double(timescale)).rounded()),
                timescale: timescale
            )
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw Failure.writerFailed(writer.error?.localizedDescription ?? "append")
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        if writer.status == .failed {
            throw Failure.writerFailed(writer.error?.localizedDescription ?? "finishWriting")
        }
    }

    private func makePixelBuffer(gray: [UInt8]) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &buffer
        )
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
