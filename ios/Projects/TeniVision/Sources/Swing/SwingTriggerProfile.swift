import Foundation

/// 트리거의 임계값 묶음.
///
/// ## ⚠️ 여기 적힌 숫자는 실측값이 아니다
///
/// 실제 임계는 0-B 촬영 영상과 코치 자문(#54)이 있어야 정해진다. 지금 값은
/// **잠정값**이며, 테스트는 값이 아니라 거동을 고정한다 — 임계를 바꿔도
/// 테스트는 통과해야 하고, 히스테리시스를 없애면 깨져야 한다.
///
/// 상황별 조정은 [비전 파이프라인 3.3](../../../../docs/02-설계/VISION-PIPELINE.md)이
/// 정했다. `CaptureSituation` → 프로파일 매핑은 **호출부**가 한다 —
/// `TeniVision`은 `Domain`을 모른다.
public struct SwingTriggerProfile: Sendable, Equatable {

    /// 이 각속도를 넘으면 스윙이 시작된 것으로 본다. rad/s.
    public let enterAngularVelocity: Double
    /// 이 아래로 떨어져야 끝난 것으로 본다. **진입보다 낮다** — 그 사이는
    /// 상태를 바꾸지 않는 완충 구간이다.
    public let exitAngularVelocity: Double
    /// 진입 임계를 넘은 상태가 이만큼 이어져야 한다. 순간적인 튐을 거른다.
    public let minimumDuration: TimeInterval
    /// 직전 트리거로부터 이 시간 안에는 다시 울리지 않는다.
    /// 같은 스윙을 두 번 잡는 것을 막는다.
    public let refractoryPeriod: TimeInterval
    /// 후보 구간을 트리거 시각에서 앞뒤로 얼마나 잡을지.
    public let preRoll: TimeInterval
    public let postRoll: TimeInterval
    /// 손목이 어깨 중점에 가까우면 각이 폭주한다. 어깨너비 대비 이 비율
    /// 미만이면 신호로 치지 않는다.
    public let minimumRadiusRatio: Double
    /// 이 아래 신뢰도의 관절은 없는 것으로 친다.
    public let minimumConfidence: Double
    /// 쓸 수 없는 프레임이 이만큼 이어지면 진행 중이던 트리거를 버린다.
    public let maximumGap: TimeInterval

    public init(
        enterAngularVelocity: Double,
        exitAngularVelocity: Double,
        minimumDuration: TimeInterval,
        refractoryPeriod: TimeInterval = 0.8,
        preRoll: TimeInterval = 2.0,
        postRoll: TimeInterval = 2.0,
        minimumRadiusRatio: Double = 0.5,
        minimumConfidence: Double = 0.3,
        maximumGap: TimeInterval = 0.25
    ) {
        precondition(
            exitAngularVelocity < enterAngularVelocity,
            "이탈 임계가 진입 임계보다 낮아야 히스테리시스가 성립한다"
        )
        precondition(minimumDuration >= 0, "최소 지속시간은 음수일 수 없다")
        precondition(preRoll >= 0 && postRoll >= 0, "구간 길이는 음수일 수 없다")
        self.enterAngularVelocity = enterAngularVelocity
        self.exitAngularVelocity = exitAngularVelocity
        self.minimumDuration = minimumDuration
        self.refractoryPeriod = refractoryPeriod
        self.preRoll = preRoll
        self.postRoll = postRoll
        self.minimumRadiusRatio = minimumRadiusRatio
        self.minimumConfidence = minimumConfidence
        self.maximumGap = maximumGap
    }

    /// 랠리 · 시합 · 레슨 · 볼머신.
    public static let `default` = SwingTriggerProfile(
        enterAngularVelocity: 8.0,
        exitAngularVelocity: 5.0,
        minimumDuration: 0.08
    )

    /// 벽치기. 벽이 가까워 스윙이 압축되므로 **피크가 낮고 짧다** —
    /// 기본값을 쓰면 통째로 놓친다. 근거: 비전 파이프라인 3.3
    public static let wall = SwingTriggerProfile(
        enterAngularVelocity: 5.0,
        exitAngularVelocity: 3.0,
        minimumDuration: 0.05
    )
}
