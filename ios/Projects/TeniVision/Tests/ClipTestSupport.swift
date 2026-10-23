import AVFoundation
import CoreVideo
import Foundation
@testable import TeniVision

/// 테스트용 프레임.
///
/// `@unchecked Sendable`인 이유: `CVPixelBuffer`는 `CVBuffer`(class)의
/// 별칭이고 Sendable이 아니다. 여기서는 만든 뒤 읽기만 하고 한 테스트
/// 안에서만 쓰므로 안전하다. 생산 경로는 `CMReadySampleBuffer`(진짜
/// Sendable)를 감싸므로 이 우회가 필요하지 않다.
struct TestFrame: ClipFrame, @unchecked Sendable {
    let seconds: TimeInterval
    private let buffer: CVPixelBuffer

    init(seconds: TimeInterval, buffer: CVPixelBuffer) {
        self.seconds = seconds
        self.buffer = buffer
    }

    func withPixelBuffer<Result: Sendable>(
        _ body: (CVPixelBuffer) throws -> Result
    ) rethrows -> Result {
        try body(buffer)
    }
}

enum ClipFixture {
    /// H.264는 짝수 크기를 요구한다. 작게 잡아 인코딩 비용을 줄인다.
    static let width = 64
    static let height = 48

    static func pixelBuffer(luma: UInt8 = 128) -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &created
        )
        guard status == kCVReturnSuccess, let buffer = created else {
            fatalError("픽셀 버퍼를 만들 수 없다: \(status)")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            memset(base, Int32(luma), bytesPerRow * height)
        }
        return buffer
    }

    /// `from`부터 `to`까지 `fps` 간격의 프레임. 끝을 포함한다.
    ///
    /// 시각을 `index / fps`로 만든다 — 누적 덧셈은 부동소수 오차가 쌓여
    /// 경계 판정이 흔들린다.
    static func frames(from: TimeInterval, to: TimeInterval, fps: Double) -> [TestFrame] {
        let first = Int((from * fps).rounded())
        let last = Int((to * fps).rounded())
        return (first...last).map { index in
            TestFrame(seconds: Double(index) / fps, buffer: pixelBuffer())
        }
    }

    static func candidate(
        triggeredAt: TimeInterval,
        profile: SwingTriggerProfile = .default,
        peak: Double = 12.0
    ) -> SwingCandidate {
        SwingCandidate(
            triggeredAt: triggeredAt,
            range: (triggeredAt - profile.preRoll)...(triggeredAt + profile.postRoll),
            peakAngularVelocity: peak
        )
    }

    /// 테스트마다 다른 빈 디렉터리.
    static func directory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "clip-tests/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum ReadFailure: Error, CustomStringConvertible {
    case noVideoTrack
    case cannotStart
    case readFailed(String)

    var description: String {
        switch self {
        case .noVideoTrack: "영상 트랙이 없다"
        case .cannotStart: "읽기를 시작할 수 없다"
        case .readFailed(let reason): "읽기 실패: \(reason)"
        }
    }
}

/// 쓴 파일을 **다시 열어** 프레임을 센다.
///
/// "오류 없이 끝났다"로 통과시키면 0프레임 파일도 통과한다.
///
/// ## 왜 거르는가
///
/// `copyNextSampleBuffer`는 압축 트랙에서 **샘플이 없는 버퍼도 돌려준다**
/// (PTS가 `invalid`다). 거르지 않고 세면 쓴 수보다 항상 4개 많게 나온다 —
/// 실측으로 확인했다(2→6, 10→14, 31→35, 61→65).
func sampleCount(of url: URL) async throws -> Int {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw ReadFailure.noVideoTrack
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { throw ReadFailure.cannotStart }

    var count = 0
    while let sample = output.copyNextSampleBuffer() {
        guard CMSampleBufferGetNumSamples(sample) > 0,
              sample.presentationTimeStamp.isValid else { continue }
        count += 1
    }
    // 끝까지 읽지 못한 것을 "샘플이 그만큼이다"로 통과시키면 안 된다.
    guard reader.status == .completed else {
        throw ReadFailure.readFailed(reader.error?.localizedDescription ?? "\(reader.status)")
    }
    return count
}
