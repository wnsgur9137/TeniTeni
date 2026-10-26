import Foundation

/// 포즈 관측을 트리거 입력으로 옮긴다.
///
/// 하는 일이 작다 — 관절 6개를 뽑고 시각을 붙인다. 그런데 이 변환이 틀리면
/// 트리거는 **아무 신호도 못 내면서 오류도 내지 않는다.** 그래서 따로 두고
/// 전수 검증한다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
public enum PoseFrameAdapter {

    /// - Parameter timestamp: 프레임 시계 기준 시각. **클립 녹화와 같은 시계여야
    ///   한다** — 다르면 트리거가 찾은 구간과 저장된 프레임이 어긋난다.
    public static func frame(
        from observation: some BodyPoseObservable,
        at timestamp: TimeInterval
    ) -> PoseFrame {
        var joints: [PoseJoint: PoseJointSample] = [:]
        joints.reserveCapacity(PoseJoint.allCases.count)
        for joint in PoseJoint.allCases {
            // 관측에 없는 관절은 넣지 않는다. 0 신뢰도로 채워 넣으면
            // "보이지만 못 믿는 관절"과 "안 보이는 관절"이 구분되지 않는다.
            guard let sample = observation.sample(for: joint) else { continue }
            joints[joint] = sample
        }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }
}
