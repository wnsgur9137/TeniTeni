import CoreMedia
import CoreVideo
import Foundation
import Synchronization
import Testing
@testable import Presentation

/// 사람이 없는 합성 프레임. 카메라 없이 **배선 전체**를 한 번 통과시킨다 —
/// 인테이크 래핑 → 다운스케일 → Vision 요청 → 결과 분류.
///
/// 사람이 잡히는지는 여기서 알 수 없다(실기기 항목). 확인하는 것은
/// "경로가 끊기지 않고 끝까지 간다"다.
private func makeReadyFrame(seconds: Double, width: Int = 1920, height: Int = 1080) throws -> ReadyFrame {
    var pixel: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil, width, height,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
        &pixel
    )
    #expect(status == kCVReturnSuccess)
    let buffer = try #require(pixel)

    var format: CMFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format
    )
    #expect(formatStatus == noErr)
    // 호출 인자 안에서 풀면 `#require`의 문맥 타입이 옵셔널이 되어
    // "nil이 될 수 없다"는 경고가 붙는다. 밖에서 푼다.
    let description = try #require(format)

    let ready = CMReadySampleBuffer(
        pixelBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: buffer),
        formatDescription: description,
        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
        duration: .invalid
    )
    return ReadyFrame(ready)
}

@Suite("포즈 분석 배선")
struct PoseAnalyzerTests {

    @Test("프레임 시각은 샘플의 PTS에서 나온다")
    func 프레임_시각() throws {
        let frame = try makeReadyFrame(seconds: 2.5)
        #expect(abs(frame.seconds - 2.5) < 1e-6)
    }

    @Test("원본 해상도를 빌리지 않고 읽는다")
    func 해상도() throws {
        let frame = try makeReadyFrame(seconds: 0, width: 1280, height: 720)
        #expect(frame.dimensions.width == 1280)
        #expect(frame.dimensions.height == 720)
    }

    @Test("픽셀 버퍼는 빌려주는 동안만 보인다")
    func 빌림() throws {
        let frame = try makeReadyFrame(seconds: 0)
        let width = frame.withPixelBuffer { CVPixelBufferGetWidth($0) }
        #expect(width == 1920)
    }

    /// **시뮬레이터에는 Vision 컴퓨트 디바이스가 없다** — 포즈 요청이
    /// `No available compute device for VNComputeStageMain`으로 실패한다.
    /// 그래서 "사람이 잡히는가"는 여기서 확인할 수 없다(실기기 항목).
    ///
    /// 확인하는 것은 **프레임 한 장이 결과 하나로 끝난다**는 것이다. 실패를
    /// 조용히 삼키면 화면은 "사람이 안 보입니다"를 영원히 띄우고, 사용자는
    /// 자기 자리를 의심하며 코트를 옮긴다.
    @Test("프레임 한 장은 결과 하나로 끝난다 — 실패도 삼키지 않는다")
    func 결과_누락_없음() async throws {
        let analyzer = PoseAnalyzer()
        let outcomes = Outcomes()

        let task = Task { await analyzer.run { outcomes.append($0) } }
        analyzer.submit(try makeReadyFrame(seconds: 0))
        analyzer.finish()
        await task.value

        let collected = outcomes.all
        #expect(collected.count == 1)
        switch collected.first {
        // 실기기: 사람이 없으니 notFound. 시뮬레이터: Vision이 못 돌아 failed.
        case .notFound, .failed: break
        case .detected: Issue.record("합성 프레임에서 사람이 잡힐 수는 없다")
        case nil: Issue.record("결과가 하나도 오지 않았다")
        }
    }

    @Test("스트림이 끝나면 분석도 끝난다")
    func 종료() async {
        let analyzer = PoseAnalyzer()
        let task = Task { await analyzer.run { _ in } }
        analyzer.finish()
        await task.value
        #expect(task.isCancelled == false)
    }
}

/// 결과 수집함. 콜백이 분석 Task에서 불리므로 잠금을 둔다.
/// `@unchecked Sendable`을 쓰지 않는다 — 동시성 6.1의 4항.
private final class Outcomes: Sendable {
    private let storage = Mutex<[PoseOutcome]>([])

    func append(_ outcome: PoseOutcome) {
        storage.withLock { $0.append(outcome) }
    }

    var all: [PoseOutcome] { storage.withLock { $0 } }
}
