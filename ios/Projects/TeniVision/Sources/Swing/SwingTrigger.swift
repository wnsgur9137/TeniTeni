import CoreGraphics
import Foundation

/// 트리거가 잡아낸 스윙 후보 구간.
public struct SwingCandidate: Sendable, Equatable {
    /// 손목이 몸통선을 **교차한** 프레임의 시각. 구간의 기준점이다.
    public let triggeredAt: TimeInterval
    /// 꺼내야 할 시간 범위. `TimedRingBuffer.range(from:to:)`에 그대로 넣는다.
    ///
    /// **끝이 미래다.** 트리거가 울린 시점에는 아직 다 담기지 않았으므로,
    /// 호출부가 `postRoll`만큼 기다린 뒤 꺼내야 한다.
    public let range: ClosedRange<TimeInterval>
    /// 이 에피소드에서 관측한 최대 각속도. rad/s. 튜닝과 진단에 쓴다.
    public let peakAngularVelocity: Double

    public init(triggeredAt: TimeInterval, range: ClosedRange<TimeInterval>, peakAngularVelocity: Double) {
        self.triggeredAt = triggeredAt
        self.range = range
        self.peakAngularVelocity = peakAngularVelocity
    }
}

/// 포즈 프레임을 하나씩 먹고 스윙 후보를 내놓는 상태 기계.
///
/// 조건은 셋이 **동시에** 성립해야 한다 — 각속도가 임계를 넘고, 손목이
/// 몸통선을 교차하고, 그 상태가 최소 지속시간을 채운다.
/// 근거: [비전 파이프라인 3.3](../../../../docs/02-설계/VISION-PIPELINE.md)
///
/// ## 왜 각속도인가
///
/// 손목의 선속도는 **촬영 거리에 종속된다.** 정규화 좌표라 8m에서 찍으면
/// 같은 스윙이 절반 값으로 나온다. 어깨 중점 기준 각속도는 피사체 크기에
/// 무관하다. 대신 손목이 몸 중심에 가까우면 각이 폭주하므로 반경 하한으로
/// 막는다.
///
/// ## 왜 actor가 아닌가
///
/// [동시성 6.1](../../../../docs/02-설계/CONCURRENCY.md)이 "순서가 중요한
/// 처리는 actor가 아니라 단일 Task"로 정했다. actor는 `await` 지점에서
/// 재진입되어 순서 보장이 코드에서 사라진다. 프레임 파이프라인은 이미
/// 단일 Task가 순서대로 돌린다.
///
/// 근거: docs/07-기획/SPEC-0085-swing-trigger.md
public struct SwingTrigger: Sendable {

    public let profile: SwingTriggerProfile
    /// 라켓을 든 쪽. 이것이 없으면 어느 손목을 볼지 정할 수 없다.
    public let racketSide: RacketSide

    /// 직전 **쓸 수 있었던** 프레임. 각속도는 두 프레임의 차에서 나온다.
    private var previous: (timestamp: TimeInterval, angle: Double, side: Double)?
    private var lastUsableAt: TimeInterval?

    // 에피소드 상태 — 하나의 "무장 → 해제" 구간
    private var armedSince: TimeInterval?
    private var crossingAt: TimeInterval?
    private var peakAngularVelocity: Double = 0
    /// 이 에피소드에서 이미 냈거나(또는 간격 때문에 막혔다). 해제될 때 풀린다.
    private var episodeClosed = false

    private var lastTriggerAt: TimeInterval?

    public init(profile: SwingTriggerProfile = .default, racketSide: RacketSide) {
        self.profile = profile
        self.racketSide = racketSide
    }

    /// 프레임 하나를 먹인다. 후보가 확정된 프레임에서만 값이 나온다.
    ///
    /// - Note: 타임스탬프는 단조 증가해야 한다. 역행하는 입력은 상정하지 않는다
    ///   — `TimedRingBuffer`와 같은 전제다.
    public mutating func process(_ frame: PoseFrame) -> SwingCandidate? {
        guard let measurement = measure(frame) else {
            // 쓸 수 없는 프레임이 이어지면 진행 중이던 스윙을 버린다.
            // 프레임 밖으로 나간 사람을 스윙으로 만들지 않기 위해서다.
            if let last = lastUsableAt, frame.timestamp - last > profile.maximumGap {
                closeEpisode()
            }
            // 끊긴 뒤의 각을 이어 붙이면 없는 각속도가 생긴다.
            previous = nil
            return nil
        }

        defer {
            lastUsableAt = frame.timestamp
            previous = (frame.timestamp, measurement.angle, measurement.side)
        }

        guard let previous else { return nil }
        let dt = frame.timestamp - previous.timestamp
        guard dt > 0 else { return nil }
        guard dt <= profile.maximumGap else {
            // 사이가 비었다 — 그 틈의 각 변화를 알 수 없으므로 버린다.
            closeEpisode()
            return nil
        }

        let angularVelocity = abs(Self.wrap(measurement.angle - previous.angle)) / dt
        updateArming(with: angularVelocity, at: frame.timestamp)

        // 교차는 무장 중에만 센다. 쉬면서 팔을 넘기는 것은 스윙이 아니다.
        if armedSince != nil, crossingAt == nil, previous.side * measurement.side < 0 {
            crossingAt = frame.timestamp
        }

        return emit(at: frame.timestamp)
    }

    public mutating func reset() {
        previous = nil
        lastUsableAt = nil
        lastTriggerAt = nil
        closeEpisode()
    }

    // MARK: - 무장

    private mutating func updateArming(with angularVelocity: Double, at timestamp: TimeInterval) {
        if angularVelocity >= profile.enterAngularVelocity {
            if armedSince == nil {
                armedSince = timestamp
                crossingAt = nil
                peakAngularVelocity = 0
                episodeClosed = false
            }
            peakAngularVelocity = max(peakAngularVelocity, angularVelocity)
        } else if angularVelocity < profile.exitAngularVelocity {
            closeEpisode()
        } else if armedSince != nil {
            // 두 임계 사이는 완충 구간이다. 무장을 유지해 지속시간이
            // 떨림 때문에 다시 세어지지 않게 한다.
            peakAngularVelocity = max(peakAngularVelocity, angularVelocity)
        }
    }

    private mutating func closeEpisode() {
        armedSince = nil
        crossingAt = nil
        peakAngularVelocity = 0
        episodeClosed = false
    }

    // MARK: - 확정

    private mutating func emit(at timestamp: TimeInterval) -> SwingCandidate? {
        guard !episodeClosed,
              let armedSince,
              let crossingAt,
              timestamp - armedSince >= profile.minimumDuration
        else { return nil }

        // 같은 스윙을 두 번 잡지 않는다. 채터링과는 다른 문제라
        // 히스테리시스가 아니라 간격으로 막는다.
        if let lastTriggerAt, crossingAt - lastTriggerAt < profile.refractoryPeriod {
            episodeClosed = true
            return nil
        }

        episodeClosed = true
        lastTriggerAt = crossingAt
        return SwingCandidate(
            triggeredAt: crossingAt,
            range: (crossingAt - profile.preRoll)...(crossingAt + profile.postRoll),
            peakAngularVelocity: peakAngularVelocity
        )
    }

    // MARK: - 기하

    private struct Measurement {
        /// 어깨 중점 기준 손목 벡터의 각. 라디안 — 동시성 6.7
        let angle: Double
        /// 몸통선 기준 부호 있는 거리. 부호가 바뀌면 교차다.
        let side: Double
    }

    private func measure(_ frame: PoseFrame) -> Measurement? {
        let minimum = profile.minimumConfidence
        guard let leftShoulder = frame.point(.leftShoulder, minimumConfidence: minimum),
              let rightShoulder = frame.point(.rightShoulder, minimumConfidence: minimum),
              let leftHip = frame.point(.leftHip, minimumConfidence: minimum),
              let rightHip = frame.point(.rightHip, minimumConfidence: minimum),
              let wrist = frame.point(racketSide.wrist, minimumConfidence: minimum)
        else { return nil }

        let shoulderMid = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2,
            y: (leftShoulder.y + rightShoulder.y) / 2
        )
        let hipMid = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)

        let shoulderWidth = hypot(leftShoulder.x - rightShoulder.x, leftShoulder.y - rightShoulder.y)
        guard shoulderWidth > 0 else { return nil }

        // 몸통 축. 사람이 기울어져도 따라가므로 화면 수직선보다 안정적이다.
        let axis = CGPoint(x: shoulderMid.x - hipMid.x, y: shoulderMid.y - hipMid.y)
        let axisLength = hypot(axis.x, axis.y)
        guard axisLength > 0 else { return nil }

        let fromShoulder = CGPoint(x: wrist.x - shoulderMid.x, y: wrist.y - shoulderMid.y)
        let radius = hypot(fromShoulder.x, fromShoulder.y)
        // 손목이 어깨 중점에 붙으면 각이 폭주한다. 그 프레임은 신호가 아니다.
        guard radius / shoulderWidth >= profile.minimumRadiusRatio else { return nil }

        let fromHip = CGPoint(x: wrist.x - hipMid.x, y: wrist.y - hipMid.y)
        let side = (axis.x * fromHip.y - axis.y * fromHip.x) / axisLength

        return Measurement(angle: atan2(fromShoulder.y, fromShoulder.x), side: side)
    }

    /// 각 차이를 (-π, π]로 접는다. 접지 않으면 179° → -179°가 358°로 읽힌다.
    private static func wrap(_ radians: Double) -> Double {
        var value = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value <= -.pi { value += 2 * .pi }
        return value
    }
}
