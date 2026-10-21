import CoreGraphics
import Foundation
import Testing
@testable import TeniVision

// MARK: - 합성 시계열

/// 어깨 중점 (0.50, 0.60), 엉덩이 중점 (0.50, 0.40).
/// 몸통 축이 수직이므로 **손목의 x가 0.50을 지날 때 교차**한다 —
/// 각으로는 90°와 270°다.
private func pose(
    at timestamp: TimeInterval,
    degrees: Double,
    radius: Double = 0.18,
    confidence: Double = 0.9,
    wrist joint: PoseJoint = .rightWrist,
    shoulderWidth: Double = 0.10
) -> PoseFrame {
    let radians = degrees * .pi / 180
    let wrist = CGPoint(x: 0.50 + radius * cos(radians), y: 0.60 + radius * sin(radians))
    func sample(_ x: Double, _ y: Double) -> PoseJointSample {
        PoseJointSample(point: CGPoint(x: x, y: y), confidence: confidence)
    }
    return PoseFrame(
        timestamp: timestamp,
        joints: [
            .leftShoulder: sample(0.50 - shoulderWidth / 2, 0.60),
            .rightShoulder: sample(0.50 + shoulderWidth / 2, 0.60),
            .leftHip: sample(0.46, 0.40),
            .rightHip: sample(0.54, 0.40),
            joint: PoseJointSample(point: wrist, confidence: confidence),
        ]
    )
}

/// 한 구간 동안 손목이 일정한 각속도로 돈다.
private struct Phase {
    var seconds: TimeInterval
    /// rad/s. 트리거의 임계와 같은 단위로 적어야 테스트를 읽을 수 있다.
    var angularVelocity: Double = 0
    var radius: Double = 0.18
    var confidence: Double = 0.9
}

/// - Note: 프레임 수를 `(seconds × fps)`를 반올림해 정하므로 **구간 길이가
///   요청값과 조금 다르다** — 0.03초 @120fps는 4프레임 = 0.0333초다.
///   `maximumGap` 경계를 따지는 테스트에서는 그 차이를 감안해야 한다.
private func timeline(
    _ phases: [Phase],
    startDegrees: Double = 0,
    fps: Double = 120,
    wrist: PoseJoint = .rightWrist
) -> [PoseFrame] {
    let dt = 1 / fps
    var frames: [PoseFrame] = []
    var t: TimeInterval = 0
    var degrees = startDegrees
    for phase in phases {
        let steps = Int((phase.seconds * fps).rounded())
        let degreesPerSecond = phase.angularVelocity * 180 / .pi
        for _ in 0..<steps {
            frames.append(
                pose(
                    at: t,
                    degrees: degrees,
                    radius: phase.radius,
                    confidence: phase.confidence,
                    wrist: wrist
                )
            )
            degrees += degreesPerSecond * dt
            t += dt
        }
    }
    return frames
}

private func candidates(
    _ frames: [PoseFrame],
    profile: SwingTriggerProfile = .default,
    side: RacketSide = .right
) -> [SwingCandidate] {
    var trigger = SwingTrigger(profile: profile, racketSide: side)
    return frames.compactMap { trigger.process($0) }
}

/// 몸통선을 가로지르는 한 번의 빠른 스윙. 기본 프로파일의 진입 임계(8.0)를 넘는다.
private func fullSwing() -> [Phase] {
    [Phase(seconds: 0.35, angularVelocity: 200 * .pi / 180 / 0.35)]
}

/// 무장 조건을 채우기에 충분히 긴 등속 접근. 4°/프레임 = 8.38 rad/s.
private func approach(to endDegrees: Double, from startDegrees: Double, fps: Double = 120)
    -> [(t: TimeInterval, degrees: Double)]
{
    var out: [(TimeInterval, Double)] = []
    var degrees = startDegrees
    var t: TimeInterval = 0
    while degrees <= endDegrees {
        out.append((t, degrees))
        degrees += 4
        t += 1 / fps
    }
    return out.map { (t: $0.0, degrees: $0.1) }
}

// MARK: -

@Suite("SwingTrigger")
struct SwingTriggerTests {

    // MARK: - 잡는다

    @Test("몸통선을 가로지르는 빠른 스윙을 한 번 잡는다")
    func 스윙_한_번() {
        let found = candidates(timeline(fullSwing()))
        #expect(found.count == 1)
        // 합성 각속도는 200°/0.35s = 9.97 rad/s다. 임계와 비교하면
        // 구조적으로 참이라 아무것도 보장하지 못하므로 실측값과 맞춘다.
        #expect(abs((found.first?.peakAngularVelocity ?? 0) - 9.97) < 0.1)
    }

    @Test("후보 구간은 교차 시각에서 preRoll 앞, postRoll 뒤다")
    func 구간() {
        // 앞뒤를 다르게 둔다. 2초·2초로 재면 **맞바꿔도 통과**한다.
        let profile = SwingTriggerProfile(
            enterAngularVelocity: 8.0,
            exitAngularVelocity: 5.0,
            minimumDuration: 0.08,
            preRoll: 1.5,
            postRoll: 3.0
        )
        guard let found = candidates(timeline(fullSwing()), profile: profile).first else {
            Issue.record("후보가 없다")
            return
        }
        #expect(abs(found.triggeredAt - 0.158) < 0.02)
        #expect(abs(found.range.lowerBound - (found.triggeredAt - 1.5)) < 1e-9)
        #expect(abs(found.range.upperBound - (found.triggeredAt + 3.0)) < 1e-9)
    }

    @Test("왼손잡이도 잡는다")
    func 왼손잡이() {
        let frames = timeline(fullSwing(), wrist: .leftWrist)
        #expect(candidates(frames, side: .left).count == 1)
    }

    // MARK: - 히스테리시스

    /// 각속도가 두 임계 **사이**로 잠깐 내려앉아도 무장이 풀리면 안 된다.
    /// 풀리면 최소 지속시간이 다시 세어지고, 이미 지나간 교차가 잊힌다.
    @Test("완충 구간으로 떨어져도 진행 중인 스윙을 놓치지 않는다")
    func 히스테리시스() {
        let frames = timeline(
            [
                Phase(seconds: 0.03, angularVelocity: 10),   // 교차. 아직 최소 지속시간 미달
                Phase(seconds: 0.06, angularVelocity: 6),    // 완충 구간 (5 < 6 < 8)
                Phase(seconds: 0.05, angularVelocity: 10),
            ],
            startDegrees: 80
        )
        #expect(candidates(frames).count == 1)
    }

    // MARK: - 재트리거 차단

    @Test("0.8초 안의 두 번째 스윙은 같은 스윙으로 보고 버린다")
    func 재트리거_차단() {
        let frames = timeline(fullSwing() + [Phase(seconds: 0.4)] + fullSwing(), startDegrees: 0)
        #expect(candidates(frames).count == 1)
    }

    @Test("간격이 충분하면 두 번 다 잡는다")
    func 두_스윙() {
        let frames = timeline(fullSwing() + [Phase(seconds: 1.2)] + fullSwing(), startDegrees: 0)
        #expect(candidates(frames).count == 2)
    }

    /// 벽치기처럼 팔이 멈추지 않는 동작에서는 각속도가 이탈 임계 아래로
    /// 떨어지지 않는다. 무장 해제를 재발화의 조건으로 삼으면 두 번째
    /// 스윙이 **간격과 무관하게 영구히 막힌다.**
    @Test("쉬지 않고 도는 동안에도 간격만 지나면 다시 잡는다")
    func 연속_회전() {
        let frames = timeline([Phase(seconds: 2.5, angularVelocity: 10)], startDegrees: 0)
        let found = candidates(frames)
        #expect(found.count == 3)
        for (earlier, later) in zip(found, found.dropFirst()) {
            #expect(later.triggeredAt - earlier.triggeredAt >= 0.8)
        }
    }

    // MARK: - 교차 판정

    /// 그라운드스트로크의 손목은 **몸통선을 지나는 바로 그 순간** 어깨
    /// 중점에 가장 가깝다. 반경 하한에 걸린 프레임을 통째로 버리면
    /// 그 교차를 놓쳐 스윙이 사라진다. 각속도만 끊고 위치는 계속 본다.
    @Test("교차 순간 손목이 몸 중심에 가까워도 잡는다")
    func 교차_프레임의_반경_하한() {
        let frames = timeline(
            [
                Phase(seconds: 0.145, angularVelocity: 10),                 // 무장
                Phase(seconds: 0.030, angularVelocity: 10, radius: 0.02),   // 교차. 반경 하한 미달
                Phase(seconds: 0.100, angularVelocity: 10),
            ],
            startDegrees: 0
        )
        #expect(candidates(frames).count == 1)
    }

    /// 손목이 몸통선 **위에 정확히** 놓이는 프레임이 끼면, 부호의 곱으로
    /// 판정하는 구현은 들어가는 곱과 나오는 곱이 모두 0이 되어 교차를
    /// 통째로 잃는다. 정규화 좌표에서는 부동소수점 흡수로 실제로 0이 된다.
    @Test("몸통선 위에 정확히 놓이는 프레임이 끼어도 교차를 본다")
    func 선_위의_프레임() {
        var frames = approach(to: 86, from: 34).map { pose(at: $0.t, degrees: $0.degrees) }
        let dt = 1.0 / 120
        let last = frames.count
        frames.append(pose(at: Double(last) * dt, degrees: 90))      // side == 0
        frames.append(pose(at: Double(last + 1) * dt, degrees: 94))
        #expect(candidates(frames).count == 1)
    }

    // MARK: - 헛잡지 않는다

    @Test("몸통선을 넘지 않는 빠른 팔 움직임은 스윙이 아니다")
    func 공_줍기() {
        // 10° → 80° → 10°. 빠르지만 한쪽에 머문다.
        let frames = timeline(
            [
                Phase(seconds: 0.122, angularVelocity: 10),
                Phase(seconds: 0.122, angularVelocity: -10),
            ],
            startDegrees: 10
        )
        #expect(candidates(frames).isEmpty)
    }

    @Test("손목이 몸 중심에 붙어 각이 폭주해도 잡지 않는다")
    func 반경_하한() {
        // 반경 0.02 / 어깨너비 0.10 = 0.2 < 0.5 → 각속도를 낼 수 없어 무장되지 않는다
        let frames = timeline(
            [Phase(seconds: 0.5, angularVelocity: 40, radius: 0.02)],
            startDegrees: 0
        )
        #expect(candidates(frames).isEmpty)
    }

    @Test("신뢰도가 낮은 관절로는 잡지 않는다")
    func 저신뢰도() {
        let frames = timeline(
            [Phase(seconds: 0.35, angularVelocity: 10, confidence: 0.1)],
            startDegrees: 0
        )
        #expect(candidates(frames).isEmpty)
    }

    @Test("어깨가 한 점으로 겹치면 기준을 세울 수 없어 잡지 않는다")
    func 어깨너비_0() {
        let frames = (0..<42).map {
            pose(at: Double($0) / 120, degrees: Double($0) * 4.76, shoulderWidth: 0)
        }
        #expect(candidates(frames).isEmpty)
    }

    @Test("보는 손목이 다르면 결과가 다르다")
    func 라켓_쪽() {
        // 합성 프레임에는 오른손목만 들어 있다 — 왼손잡이 트리거는 아무것도 못 본다.
        #expect(candidates(timeline(fullSwing()), side: .left).isEmpty)
    }

    // MARK: - 결측과 시간

    /// 교차까지 끝낸 스윙이라도, 중간이 비면 그 뒤를 이어 붙이지 않는다.
    /// 사람이 프레임 밖으로 나갔다 들어온 것을 한 번의 스윙으로 만들면 안 된다.
    @Test("결측이 이어지면 진행 중이던 스윙을 버린다")
    func 결측() {
        let frames = timeline(
            [
                Phase(seconds: 0.03, angularVelocity: 10),                  // 교차
                Phase(seconds: 0.30, angularVelocity: 0, confidence: 0.05), // 0.25초 초과 결측
                Phase(seconds: 0.15, angularVelocity: 10),                  // 교차 없음
            ],
            startDegrees: 80
        )
        #expect(candidates(frames).isEmpty)
    }

    /// 최소 지속시간을 **벽시계 시간**으로 재면, 그 사이에 신호가 없어도
    /// 조건이 충족된다. 결측 0.2초가 임계 초과 0.2초를 대신하면 안 된다.
    @Test("결측이 최소 지속시간을 대신 채우지 못한다")
    func 결측과_지속시간() {
        let frames = timeline(
            [
                Phase(seconds: 0.03, angularVelocity: 10),                  // 교차. 실측 0.025초
                Phase(seconds: 0.20, angularVelocity: 0, confidence: 0.05), // 결측 — 허용 범위 안
                Phase(seconds: 0.05, angularVelocity: 10),                  // 더해도 0.08초에 못 미친다
            ],
            startDegrees: 80
        )
        #expect(candidates(frames).isEmpty)
    }

    @Test("쓸 수 있는 프레임 사이가 비어도 진행 중이던 스윙을 버린다")
    func 프레임_끊김() {
        let dt = 1.0 / 120
        var frames = [80.0, 84, 88, 92].enumerated().map {
            pose(at: Double($0.offset) * dt, degrees: $0.element)   // 교차. 지속시간 미달
        }
        // 0.3초 뒤에 멀쩡한 프레임이 온다 — 그 틈의 변화는 알 수 없다.
        var t = 3 * dt + 0.3
        var degrees = 96.0
        while degrees <= 130 {
            frames.append(pose(at: t, degrees: degrees))
            degrees += 4
            t += dt
        }
        #expect(candidates(frames).isEmpty)
    }

    @Test("역행하는 타임스탬프는 상태를 흔들지 않는다")
    func 역행() {
        var frames = timeline(fullSwing())
        // 다 끝난 뒤에 과거 프레임이 끼어든다.
        frames.append(pose(at: 0.01, degrees: 10))
        let found = candidates(frames)
        #expect(found.count == 1)
        #expect(abs((found.first?.triggeredAt ?? 0) - 0.158) < 0.02)
    }

    // MARK: - 상황별 프로파일

    @Test("벽치기 프로파일은 기본값이 놓치는 낮은 피크를 잡는다")
    func 벽치기() {
        let frames = timeline([Phase(seconds: 0.6, angularVelocity: 6.5)], startDegrees: 5)
        #expect(candidates(frames, profile: .default).isEmpty)
        #expect(candidates(frames, profile: .wall).count == 1)
    }

    // MARK: - 리셋

    @Test("reset은 간격 차단까지 지운다")
    func 리셋() {
        var trigger = SwingTrigger(profile: .default, racketSide: .right)
        let first = timeline(fullSwing()).compactMap { trigger.process($0) }
        trigger.reset()
        // 같은 시계열을 다시 먹인다. 간격 차단이 남아 있으면 두 번째는 안 나온다.
        let second = timeline(fullSwing()).compactMap { trigger.process($0) }
        #expect(first.count == 1)
        #expect(second.count == 1)
    }
}
