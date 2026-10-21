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
    ///
    /// 세션 시작 직후면 하한이 음수일 수 있다. `TimedRingBuffer`는 범위로
    /// 걸러내므로 버퍼 밖 하한은 무해하다 — 가진 만큼만 나온다.
    public let range: ClosedRange<TimeInterval>
    /// 무장 이후 **발화 시점까지** 관측한 최대 각속도. rad/s.
    ///
    /// 에피소드 전체의 최대가 아니다 — 발화는 최소 지속시간만 채우면
    /// 일어나므로, 피크가 그 뒤에 오면 이 값에 들어오지 않는다. 튜닝에
    /// 쓸 때 그 점을 염두에 둬야 한다.
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
/// ## 위치와 각속도를 따로 다룬다
///
/// 반경 하한에 걸린 프레임은 **각속도를 못 내지만 위치는 안다.** 둘을 한
/// 덩어리로 버리면 교차를 놓친다 — 그라운드스트로크의 손목은 몸통선을
/// 지나는 바로 그 순간 어깨 중점에 가장 가깝기 때문이다. 각속도는 끊고
/// 교차 판정은 이어간다.
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

    /// 각속도를 낼 수 있었던 직전 프레임. 반경 하한에 걸리면 끊는다.
    private var previousAngle: (timestamp: TimeInterval, angle: Double)?
    /// 마지막으로 본 **0이 아닌** 몸통선 부호.
    ///
    /// 0을 건너뛰는 이유: 손목이 선 위에 정확히 놓이는 프레임이 끼면
    /// 들어가는 곱과 나오는 곱이 모두 0이 되어 교차가 통째로 사라진다.
    /// 정규화 좌표에서는 부동소수점 흡수로 **실제로 정확히 0이 된다.**
    private var lastNonZeroSide: Double?
    /// 관절이 보였던 마지막 시각.
    private var lastUsableAt: TimeInterval?

    private var isArmed = false
    /// 무장 중 **각속도를 실제로 평가한** 시간의 합.
    ///
    /// 벽시계 시간이 아니다. `armedSince`부터의 경과로 재면 그 사이가
    /// 결측이어도 지속시간이 채워진다 — 신호 없이 조건이 충족된다.
    private var armedDuration: TimeInterval = 0
    private var crossingAt: TimeInterval?
    private var peakAngularVelocity: Double = 0
    private var lastTriggerAt: TimeInterval?

    public init(profile: SwingTriggerProfile = .default, racketSide: RacketSide) {
        self.profile = profile
        self.racketSide = racketSide
    }

    /// 프레임 하나를 먹인다. 후보가 확정된 프레임에서만 값이 나온다.
    public mutating func process(_ frame: PoseFrame) -> SwingCandidate? {
        guard let geometry = measure(frame) else {
            // 관절이 안 보인다 — 위치도 각속도도 모른다. 이어지면 버린다.
            // 프레임 밖으로 나간 사람을 스윙으로 만들지 않기 위해서다.
            if let lastUsableAt, frame.timestamp - lastUsableAt > profile.maximumGap {
                disarm()
            }
            previousAngle = nil
            return nil
        }

        // 타임스탬프가 멈췄거나 역행한 프레임은 **상태를 건드리지 않고** 버린다.
        // 갱신하면 결측 판정의 기준이 과거로 되감긴다.
        if let lastUsableAt, frame.timestamp <= lastUsableAt { return nil }

        // 쓸 수 있는 프레임 사이가 비어도 마찬가지다 — 그 틈의 변화를 모른다.
        if let lastUsableAt, frame.timestamp - lastUsableAt > profile.maximumGap {
            disarm()
        }
        lastUsableAt = frame.timestamp

        if let angle = geometry.angle {
            if let previousAngle {
                let dt = frame.timestamp - previousAngle.timestamp
                if dt > 0, dt <= profile.maximumGap {
                    let velocity = abs(Self.wrap(angle - previousAngle.angle)) / dt
                    updateArming(with: velocity, over: dt)
                }
            }
            previousAngle = (frame.timestamp, angle)
        } else {
            // 각은 못 낸다. 이어 붙이면 없는 각속도가 생긴다.
            previousAngle = nil
        }

        // 교차는 위치만 있으면 판정된다. 각속도를 못 낸 프레임에서도 본다.
        if geometry.side != 0 {
            if isArmed, crossingAt == nil, let lastNonZeroSide,
               lastNonZeroSide * geometry.side < 0 {
                crossingAt = frame.timestamp
            }
            lastNonZeroSide = geometry.side
        }

        return emit()
    }

    public mutating func reset() {
        previousAngle = nil
        lastNonZeroSide = nil
        lastUsableAt = nil
        lastTriggerAt = nil
        disarm()
    }

    // MARK: - 무장

    private mutating func updateArming(with velocity: Double, over dt: TimeInterval) {
        if velocity < profile.exitAngularVelocity {
            disarm()
            return
        }
        // 두 임계 사이는 완충 구간이다. 무장 중이면 유지해 지속시간이
        // 떨림 때문에 다시 세어지지 않게 한다.
        guard velocity >= profile.enterAngularVelocity || isArmed else { return }
        isArmed = true
        armedDuration += dt
        peakAngularVelocity = max(peakAngularVelocity, velocity)
    }

    private mutating func disarm() {
        isArmed = false
        armedDuration = 0
        crossingAt = nil
        peakAngularVelocity = 0
    }

    // MARK: - 확정

    private mutating func emit() -> SwingCandidate? {
        guard isArmed,
              let crossing = crossingAt,
              armedDuration >= profile.minimumDuration
        else { return nil }

        // 교차는 소비한다. 울렸든 간격에 막혔든 같은 교차를 두 번 보지 않는다.
        crossingAt = nil

        // 같은 스윙을 두 번 잡지 않는다. 채터링과는 다른 문제라
        // 히스테리시스가 아니라 간격으로 막는다.
        //
        // 무장을 풀지는 않는다 — 벽치기처럼 팔이 느려지지 않는 동작에서는
        // 이탈 임계 아래로 떨어질 일이 없고, 그러면 두 번째 스윙이
        // 간격과 무관하게 영구히 막힌다.
        if let lastTriggerAt, crossing - lastTriggerAt < profile.refractoryPeriod {
            return nil
        }

        lastTriggerAt = crossing
        return SwingCandidate(
            triggeredAt: crossing,
            range: (crossing - profile.preRoll)...(crossing + profile.postRoll),
            peakAngularVelocity: peakAngularVelocity
        )
    }

    // MARK: - 기하

    private struct Geometry {
        /// 어깨 중점 기준 손목 벡터의 각. 라디안 — 동시성 6.7.
        /// 반경 하한에 걸리면 `nil`이다 — 각이 폭주하는 구간이다.
        let angle: Double?
        /// 몸통선 기준 부호 있는 거리. 부호가 바뀌면 교차다.
        let side: Double
    }

    private func measure(_ frame: PoseFrame) -> Geometry? {
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

        let fromHip = CGPoint(x: wrist.x - hipMid.x, y: wrist.y - hipMid.y)
        let side = (axis.x * fromHip.y - axis.y * fromHip.x) / axisLength

        let fromShoulder = CGPoint(x: wrist.x - shoulderMid.x, y: wrist.y - shoulderMid.y)
        let radius = hypot(fromShoulder.x, fromShoulder.y)
        // CGFloat을 Double로 명시해 둔다 — 삼항 연산자가 `nil`과 묶이면
        // 암묵 변환이 걸리지 않는다.
        let angle: Double? = radius / shoulderWidth >= profile.minimumRadiusRatio
            ? Double(atan2(fromShoulder.y, fromShoulder.x))
            : nil

        return Geometry(angle: angle, side: side)
    }

    /// 각 차이를 (-π, π]로 접는다. 접지 않으면 179° → -179°가 358°로 읽힌다.
    private static func wrap(_ radians: Double) -> Double {
        var value = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value <= -.pi { value += 2 * .pi }
        return value
    }
}
