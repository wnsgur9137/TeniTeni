import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Synchronization
import Testing
import TeniVision
@testable import Presentation

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

    /// 가짜 추정기를 끼워 **다운스케일 → 추정 → 결과 분류**를 전부 돌린다.
    /// Vision은 시뮬레이터에서 돌지 않으므로 이 경로는 가짜 없이는 검증되지 않는다.
    @Test("포즈가 잡히면 프레임 시각을 달고 나온다")
    func 검출_경로() async throws {
        let pose = PoseFrame(timestamp: 0, joints: [
            .leftShoulder: PoseJointSample(point: CGPoint(x: 0.4, y: 0.6), confidence: 0.9),
            .rightShoulder: PoseJointSample(point: CGPoint(x: 0.6, y: 0.6), confidence: 0.9),
        ])
        let analyzer = PoseAnalyzer(estimator: StubEstimator([.pose(pose)]))
        let outcomes = Outcomes()

        let task = Task { await analyzer.run { _, outcome in outcomes.append(outcome) } }
        analyzer.submit(try makeReadyFrame(seconds: 7.5))
        analyzer.finish()
        await task.value

        let collected = outcomes.all
        #expect(collected.count == 1)
        guard case .detected(let frame) = try #require(collected.first) else {
            Issue.record("검출로 분류되지 않았다")
            return
        }
        #expect(abs(frame.timestamp - 7.5) < 1e-6)
        #expect(frame.joints.count == 2)
    }

    @Test("사람이 없으면 noPerson, 어깨를 못 믿으면 unusable로 갈린다")
    func 구분() async throws {
        let analyzer = PoseAnalyzer(estimator: StubEstimator([.noPerson, .unusable]))
        let outcomes = Outcomes()

        let task = Task { await analyzer.run { _, outcome in outcomes.append(outcome) } }
        analyzer.submit(try makeReadyFrame(seconds: 1))
        // 버퍼가 1장이라 두 장을 한꺼번에 넣으면 앞이 버려질 수 있다.
        // 순서가 아니라 분류를 보는 테스트이므로 결과 수로 판정하지 않는다.
        analyzer.finish()
        await task.value

        let collected = outcomes.all
        #expect(collected.allSatisfy { $0.seconds == 1 })
        #expect(collected.contains { $0 == .noPerson(at: 1) || $0 == .unusable(at: 1) })
    }

    @Test("추정이 던지면 프레임 시각을 달고 failed로 올라온다")
    func 실패_경로() async throws {
        let analyzer = PoseAnalyzer(estimator: FailingEstimator())
        let outcomes = Outcomes()

        let task = Task { await analyzer.run { _, outcome in outcomes.append(outcome) } }
        analyzer.submit(try makeReadyFrame(seconds: 3))
        analyzer.finish()
        await task.value

        let collected = outcomes.all
        #expect(collected.count == 1)
        guard case .failed(_, let at) = try #require(collected.first) else {
            Issue.record("실패로 분류되지 않았다")
            return
        }
        #expect(at == 3)
    }

    /// **시뮬레이터에는 Vision 컴퓨트 디바이스가 없다** —
    /// `No available compute device for VNComputeStageMain`으로 실패한다.
    /// 그래서 진짜 추정기로는 "사람이 잡히는가"를 확인할 수 없다(실기기 항목).
    ///
    /// 확인하는 것은 **프레임 한 장이 결과 하나로 끝난다**는 것이다. 실패를
    /// 조용히 삼키면 화면은 "사람이 안 보입니다"를 영원히 띄우고, 사용자는
    /// 자기 자리를 의심하며 코트를 옮긴다.
    @Test("진짜 추정기에서도 프레임 한 장은 결과 하나로 끝난다")
    func 결과_누락_없음() async throws {
        let analyzer = PoseAnalyzer()
        let outcomes = Outcomes()

        let task = Task { await analyzer.run { _, outcome in outcomes.append(outcome) } }
        analyzer.submit(try makeReadyFrame(seconds: 0))
        analyzer.finish()
        await task.value

        let collected = outcomes.all
        #expect(collected.count == 1)
        switch try #require(collected.first) {
        // 실기기: 사람이 없으니 noPerson. 시뮬레이터: Vision이 못 돌아 failed.
        case .noPerson, .unusable, .failed: break
        case .detected: Issue.record("합성 프레임에서 사람이 잡힐 수는 없다")
        }
    }

    @Test("스트림이 끝나면 분석도 끝난다")
    func 종료() async {
        let analyzer = PoseAnalyzer(estimator: StubEstimator([.noPerson]))
        let task = Task { await analyzer.run { _, _ in } }
        analyzer.finish()
        // 끝나지 않으면 이 await가 돌아오지 않는다 — 그것이 이 테스트의 내용이다.
        await task.value
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
