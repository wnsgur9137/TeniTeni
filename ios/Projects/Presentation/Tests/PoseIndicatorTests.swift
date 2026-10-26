import CoreGraphics
import Foundation
import Testing
import TeniVision
@testable import Presentation

/// 이 PR이 화면에 내놓는 **유일한 출력**의 판단 로직이다. 카메라가 없으면
/// 검증할 방법이 없어서 순수 함수로 빼 뒀다.
/// `CameraController`가 `@MainActor`이므로 그 정적 멤버도 격리돼 있다.
/// 스위트를 메인에 묶는다 — 판정 함수에 `nonisolated`를 붙이는 쪽보다
/// 테스트가 실제 호출 맥락(메인에서 불린다)과 같아진다.
@MainActor
@Suite("포즈 표시 판정")
struct PoseIndicatorTests {

    private let grace = CameraController.poseGraceSeconds

    private func pose(at seconds: TimeInterval) -> PoseFrame {
        PoseFrame(timestamp: seconds, joints: [
            .leftShoulder: PoseJointSample(point: CGPoint(x: 0.4, y: 0.6), confidence: 0.9),
            .rightShoulder: PoseJointSample(point: CGPoint(x: 0.6, y: 0.6), confidence: 0.9),
        ])
    }

    private func indicator(
        _ outcome: PoseOutcome, lastDetectedAt: TimeInterval?
    ) -> CameraController.PoseIndicator? {
        CameraController.indicator(for: outcome, lastDetectedAt: lastDetectedAt, grace: grace)
    }

    @Test("포즈가 잡히면 즉시 보인다")
    func 검출() {
        #expect(indicator(.detected(pose(at: 1)), lastDetectedAt: nil) == .detected)
    }

    /// 한 번도 잡힌 적이 없으면 기다릴 이유가 없다 — 사용자는 아직
    /// 자리를 잡는 중이고, 그 순간 피드백이 가장 필요하다.
    @Test("한 번도 잡힌 적 없으면 바로 안 보인다고 말한다")
    func 최초_미검출() {
        #expect(indicator(.noPerson(at: 0.01), lastDetectedAt: nil) == .notFound)
        #expect(indicator(.unusable(at: 0.01), lastDetectedAt: nil) == .unusable)
        #expect(indicator(.failed("x", at: 0.01), lastDetectedAt: nil) == .failed("x"))
    }

    /// 한 프레임 놓친 것으로 표시를 바꾸면 6m 밖에서 읽을 수 없다.
    @Test("유예 안이면 표시를 바꾸지 않는다")
    func 유예_유지() {
        #expect(indicator(.noPerson(at: 10 + grace - 0.01), lastDetectedAt: 10) == nil)
        #expect(indicator(.unusable(at: 10 + grace - 0.01), lastDetectedAt: 10) == nil)
        // 한 프레임 오류로 "분석이 멈췄습니다"가 떴다 사라지지 않는다.
        #expect(indicator(.failed("x", at: 10 + grace - 0.01), lastDetectedAt: 10) == nil)
    }

    @Test("유예를 넘기면 바꾼다")
    func 유예_경과() {
        #expect(indicator(.noPerson(at: 10 + grace + 0.01), lastDetectedAt: 10) == .notFound)
        #expect(indicator(.unusable(at: 10 + grace + 0.01), lastDetectedAt: 10) == .unusable)
        #expect(indicator(.failed("x", at: 10 + grace + 0.01), lastDetectedAt: 10) == .failed("x"))
    }

    @Test("경계는 넘어야 바뀐다 — 같으면 유지한다")
    func 경계() {
        #expect(indicator(.noPerson(at: 10 + grace), lastDetectedAt: 10) == nil)
    }

    /// 벽시계로 재면 메인이 막혔다 풀리는 순간 멀쩡한 상태에서 뒤집힌다.
    /// 프레임 시계로 재면 간격이 8ms인 것을 안다.
    @Test("프레임 간격이 짧으면 메인이 늦게 배달해도 유지된다")
    func 프레임_시계() {
        // 포즈가 10.000에 잡히고 다음 프레임이 10.008이다. 벽시계로 300ms
        // 뒤에 배달돼도 간격은 8ms다.
        #expect(indicator(.noPerson(at: 10.008), lastDetectedAt: 10) == nil)
    }

    @Test("유예는 트리거의 결측 허용 간격과 같다")
    func 유예_값() {
        #expect(grace == SwingTriggerProfile.default.maximumGap)
    }
}
