import CoreGraphics
import Foundation
import Testing
@testable import TeniVision

// MARK: - 합성 시계열

/// 어깨 중점 (0.50, 0.60), 엉덩이 중점 (0.50, 0.40), 어깨너비 0.10.
/// 몸통 축이 수직이므로 **손목의 x가 0.50을 지날 때 교차**한다 —
/// 각으로는 90°와 270°다.
private func pose(
    at timestamp: TimeInterval,
    degrees: Double,
    radius: Double = 0.18,
    confidence: Double = 0.9
) -> PoseFrame {
    let radians = degrees * .pi / 180
    let wrist = CGPoint(x: 0.50 + radius * cos(radians), y: 0.60 + radius * sin(radians))
    func sample(_ x: Double, _ y: Double) -> PoseJointSample {
        PoseJointSample(point: CGPoint(x: x, y: y), confidence: confidence)
    }
    return PoseFrame(
        timestamp: timestamp,
        joints: [
            .leftShoulder: sample(0.45, 0.60),
            .rightShoulder: sample(0.55, 0.60),
            .leftHip: sample(0.46, 0.40),
            .rightHip: sample(0.54, 0.40),
            .rightWrist: PoseJointSample(point: wrist, confidence: confidence),
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

private func timeline(_ phases: [Phase], startDegrees: Double = 0, fps: Double = 120) -> [PoseFrame] {
    let dt = 1 / fps
    var frames: [PoseFrame] = []
    var t: TimeInterval = 0
    var degrees = startDegrees
    for phase in phases {
        let steps = Int((phase.seconds * fps).rounded())
        let degreesPerSecond = phase.angularVelocity * 180 / .pi
        for _ in 0..<steps {
            frames.append(pose(at: t, degrees: degrees, radius: phase.radius, confidence: phase.confidence))
            degrees += degreesPerSecond * dt
            t += dt
        }
    }
    return frames
}

private func candidates(
    _ frames: [PoseFrame],
    profile: SwingTriggerProfile = .default
) -> [SwingCandidate] {
    var trigger = SwingTrigger(profile: profile, racketSide: .right)
    return frames.compactMap { trigger.process($0) }
}

/// 몸통선을 가로지르는 한 번의 빠른 스윙. 기본 프로파일의 진입 임계(8.0)를 넘는다.
private func fullSwing() -> [Phase] {
    [Phase(seconds: 0.35, angularVelocity: 200 * .pi / 180 / 0.35)]
}

// MARK: -

@Suite("SwingTrigger")
struct SwingTriggerTests {

    // MARK: - 잡는다

    @Test("몸통선을 가로지르는 빠른 스윙을 한 번 잡는다")
    func 스윙_한_번() {
        let found = candidates(timeline(fullSwing()))
        #expect(found.count == 1)
        #expect(found.first?.peakAngularVelocity ?? 0 >= SwingTriggerProfile.default.enterAngularVelocity)
    }

    @Test("후보 구간은 교차 시각의 앞뒤 2초다")
    func 구간() {
        let profile = SwingTriggerProfile.default
        guard let found = candidates(timeline(fullSwing())).first else {
            Issue.record("후보가 없다")
            return
        }
        #expect(found.range.lowerBound == found.triggeredAt - profile.preRoll)
        #expect(found.range.upperBound == found.triggeredAt + profile.postRoll)
        // 교차는 스윙 중간(90°/200°)쯤이다. 0.35초 스윙이므로 0.15초 근처.
        #expect(abs(found.triggeredAt - 0.158) < 0.02)
    }

    // MARK: - 히스테리시스

    /// 각속도가 두 임계 **사이**로 잠깐 내려앉아도 무장이 풀리면 안 된다.
    /// 풀리면 최소 지속시간이 다시 세어지고, 이미 지나간 교차가 잊힌다.
    ///
    /// 이탈 임계를 진입 임계와 같게 만들면(= 히스테리시스 제거) 이 테스트가
    /// 죽는다 — 교차를 품은 에피소드가 완충 구간에서 닫히고, 뒤이은 빠른
    /// 구간에는 교차가 없다.
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
        // 반경 0.02 / 어깨너비 0.10 = 0.2 < 0.5
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

    // MARK: - 상황별 프로파일

    @Test("벽치기 프로파일은 기본값이 놓치는 낮은 피크를 잡는다")
    func 벽치기() {
        let frames = timeline([Phase(seconds: 0.6, angularVelocity: 6.5)], startDegrees: 0)
        #expect(candidates(frames, profile: .default).isEmpty)
        #expect(candidates(frames, profile: .wall).count == 1)
    }

    // MARK: - 라켓 쪽

    @Test("보는 손목이 다르면 결과가 다르다")
    func 라켓_쪽() {
        var left = SwingTrigger(profile: .default, racketSide: .left)
        // 합성 프레임에는 오른손목만 들어 있다 — 왼손잡이 트리거는 아무것도 못 본다.
        let found = timeline(fullSwing()).compactMap { left.process($0) }
        #expect(found.isEmpty)
    }

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
