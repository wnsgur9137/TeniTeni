import Foundation
import Synchronization
import Testing
@testable import Presentation

/// 데시메이터의 산술은 따로 검증한다. 여기서 보는 것은 **결합**이다 —
/// 번호 매김과 거르기와 넘기기가 실제로 맞물리는가. `captureOutput`에 묶여
/// 있으면 `AVCaptureConnection` 없이 호출할 수 없어 전혀 검증되지 않는다.
@Suite("프레임 인테이크")
struct FrameIntakeTests {

    private func intake(stride: Int) -> (FrameIntake, Counter) {
        let counter = Counter()
        let intake = FrameIntake(
            decimator: FrameDecimator(stride: stride),
            onAnalysisFrame: { _ in _ = counter.next() }
        )
        return (intake, counter)
    }

    @Test("stride 1은 전부 넘긴다")
    func 전부_통과() throws {
        let (intake, counter) = intake(stride: 1)
        for i in 0..<5 { intake.intake(try makeReadyFrame(seconds: Double(i) / 60)) }
        #expect(counter.value == 5)
    }

    /// 번호를 올린 **뒤** 값을 쓰면 0번이 1이 되어 첫 장이 버려진다.
    @Test("stride 2는 첫 장을 버리지 않고 절반을 넘긴다")
    func 절반_통과() throws {
        let (intake, counter) = intake(stride: 2)
        for i in 0..<5 { intake.intake(try makeReadyFrame(seconds: Double(i) / 120)) }
        // 0, 2, 4
        #expect(counter.value == 3)
    }

    @Test("간격을 바꾸면 그 다음 프레임부터 적용된다")
    func 간격_교체() throws {
        let (intake, counter) = intake(stride: 1)
        intake.intake(try makeReadyFrame(seconds: 0))
        #expect(counter.value == 1)

        intake.update(decimator: FrameDecimator(stride: 10))
        // 번호 1~9는 버려지고 10만 통과한다.
        for i in 1...10 { intake.intake(try makeReadyFrame(seconds: Double(i) / 120)) }
        #expect(counter.value == 2)
    }

    @Test("프레임이 들어오기 전에는 드롭도 거부도 0이다")
    func 초기_계수() {
        let (intake, _) = intake(stride: 1)
        #expect(intake.droppedCount == 0)
        #expect(intake.rejectedCount == 0)
    }

    @Test("넘긴 프레임의 시각이 보존된다")
    func 시각_보존() throws {
        let seen = Mutex<[TimeInterval]>([])
        let intake = FrameIntake(
            decimator: FrameDecimator(stride: 2),
            onAnalysisFrame: { frame in seen.withLock { $0.append(frame.seconds) } }
        )
        for i in 0..<4 { intake.intake(try makeReadyFrame(seconds: Double(i))) }
        #expect(seen.withLock { $0 } == [0, 2])
    }
}
