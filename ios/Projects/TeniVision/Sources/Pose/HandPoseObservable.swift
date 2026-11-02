import CoreGraphics
import Foundation
import Vision

/// 손 관절 중 **라켓 헤드 추정이 쓰는 둘**.
///
/// ## 왜 `PoseJoint`에 넣지 않는가
///
/// 신체 관절과 손가락 관절은 Vision에서 **다른 열거형**이고
/// (`HumanBodyPoseObservation.JointName` / `HumanHandPoseObservation.JointName`)
/// **다른 관측**에서 나온다. 한 열거형에 섞으면 `sample(for:)`이 "어느
/// 관측에서 찾아야 하는가"를 안에서 분기하게 된다.
///
/// ## 왜 21개를 다 넣지 않는가
///
/// 쓰지 않는 관절을 노출하면 가짜 구현이 그만큼 커진다. 손가락을 그리기로
/// 하면 그때 넓힌다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md 선택지 6
public enum HandJoint: String, Sendable, Hashable, CaseIterable, Codable {
    /// 손목. **신체 관측의 `PoseJoint.rightWrist`와 다른 점이다** —
    /// 이쪽은 손 관측의 것이고, `middleMCP`와 같은 추정에서 나온다.
    case wrist
    /// 가운뎃손가락 중수골. 손목과 함께 **그립 축**을 만든다.
    case middleMCP
}

/// 손 관측에서 읽는 것 **전부**.
///
/// `BodyPoseObservable`과 나란히 둔다. 같은 이유로 프로토콜을 끼운다 —
/// `HumanHandPoseObservation`에는 합성할 공개 생성자가 없고, 그것을 입력으로
/// 삼으면 라켓 헤드 추정을 실기기에서만 확인할 수 있다.
public protocol HandPoseObservable: Sendable {
    /// 관절 하나. 관측에 없으면 `nil`이다.
    ///
    /// **신뢰도로 걸러내지 않는다.** 임계 판단은 `RacketHeadEstimator`가
    /// 한다 — 두 곳에 두면 둘이 어긋난다.
    func sample(for joint: HandJoint) -> PoseJointSample?
}

/// Vision 관측을 경계에 적합시킨다. 전달만 한다.
extension HumanHandPoseObservation: HandPoseObservable {
    public func sample(for joint: HandJoint) -> PoseJointSample? {
        guard let found = self.joint(for: joint.visionName) else { return nil }
        // `NormalizedPoint`는 좌하단 원점이다. 뒤집지 않는다 — 동시성 6.7.
        return PoseJointSample(
            point: found.location.cgPoint,
            confidence: Double(found.confidence)
        )
    }
}

/// 신체와 **그 사람의 손**을 함께 주는 관측.
///
/// 라켓 헤드 추정은 둘이 다 필요하다 — 어깨너비를 자로 쓰고 손으로 방향을
/// 잡는다. 둘을 따로 받으면 호출부가 **다른 사람의 손**을 꽂을 수 있다.
///
/// `BodyPoseObservable`을 상속하는 이유: 사람을 고르는 `primary(in:)`가
/// 어깨너비를 보므로 같은 값에서 골라야 한다.
public protocol RacketPoseObservable: BodyPoseObservable {
    /// 그 쪽 손. `detectsHands`가 꺼져 있거나 손이 안 보이면 `nil`이다.
    func hand(_ side: RacketSide) -> (any HandPoseObservable)?
}

extension HumanBodyPoseObservation: RacketPoseObservable {
    public func hand(_ side: RacketSide) -> (any HandPoseObservable)? {
        switch side {
        case .left: leftHand
        case .right: rightHand
        }
    }
}

extension HandJoint {
    var visionName: HumanHandPoseObservation.JointName {
        switch self {
        case .wrist: .wrist
        case .middleMCP: .middleMCP
        }
    }
}
