import CoreGraphics
import Foundation

/// 트리거가 읽는 관절. **Vision이 내는 19개 중 6개만** 쓴다.
///
/// 더 받지 않는 이유는 두 가지다. 트리거에 필요한 것이 이것뿐이고,
/// 적게 받을수록 0-D의 어댑터가 틀릴 여지가 줄어든다.
///
/// 근거: docs/07-기획/SPEC-0085-swing-trigger.md
public enum PoseJoint: Sendable, Hashable, CaseIterable {
    case leftShoulder
    case rightShoulder
    case leftHip
    case rightHip
    case leftWrist
    case rightWrist
}

/// 라켓을 든 쪽. `Domain.Handedness`를 그대로 받지 않는다 —
/// `TeniVision`은 `Domain`에 의존하지 않는다(`Project.swift`).
/// 변환은 호출부가 한다.
public enum RacketSide: Sendable, Hashable, CaseIterable {
    case left
    case right

    public var wrist: PoseJoint {
        switch self {
        case .left: .leftWrist
        case .right: .rightWrist
        }
    }
}

/// 관절 하나의 위치와 신뢰도.
public struct PoseJointSample: Sendable, Equatable {
    /// Vision 정규화 좌표(0~1, **좌하단 원점**). 렌더 직전까지 이 좌표를
    /// 유지한다 — docs/02-설계/CONCURRENCY.md 6.7
    public let point: CGPoint
    /// 0~1. 가려진 관절은 낮게 나온다.
    public let confidence: Double

    public init(point: CGPoint, confidence: Double) {
        self.point = point
        self.confidence = confidence
    }
}

/// 포즈 한 프레임.
///
/// ## 왜 Vision 타입을 직접 받지 않는가
///
/// `HumanBodyPoseObservation`에는 합성할 공개 생성자가 없다. 그것을
/// 입력으로 삼으면 **테스트를 쓸 수 없고**, 그러면 이 작업이 성립하는
/// 유일한 이유(실기기 없이 검증된다)가 사라진다.
///
/// Vision 관측 → `PoseFrame` 어댑터는 포즈 검출(0-D #4)이 만든다.
public struct PoseFrame: Sendable, Equatable {
    /// 프레임 시각. 단조 증가한다.
    public let timestamp: TimeInterval
    public let joints: [PoseJoint: PoseJointSample]

    public init(timestamp: TimeInterval, joints: [PoseJoint: PoseJointSample]) {
        self.timestamp = timestamp
        self.joints = joints
    }

    /// 신뢰도가 기준에 못 미치면 **없는 것으로 친다.** 보간하지 않는다 —
    /// 프레임 밖으로 나간 사람을 스윙으로 만들지 않기 위해서다.
    public func point(_ joint: PoseJoint, minimumConfidence: Double) -> CGPoint? {
        guard let sample = joints[joint], sample.confidence >= minimumConfidence else { return nil }
        return sample.point
    }
}
