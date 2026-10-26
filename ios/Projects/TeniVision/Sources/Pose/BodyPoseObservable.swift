import CoreGraphics
import Foundation
import Vision

/// 어댑터가 포즈 관측에서 읽는 것 **전부**.
///
/// ## 왜 프로토콜을 끼우는가
///
/// `HumanBodyPoseObservation`은 합성할 수 없다. 생성자는
/// `init(_: VNHumanBodyPoseObservation)` 하나뿐이고 그 레거시 타입도
/// 합성할 수 없다. 관측을 어댑터의 입력으로 삼으면 **어댑터를 실기기에서만
/// 확인할 수 있다** — 그러면 1-B가 성립하는 이유(실기기 없이 검증된다)가
/// 사라진다.
///
/// `Decodable`을 타고 JSON 픽스처를 만드는 길도 있지만, 그 인코딩 포맷은
/// 문서화돼 있지 않아 OS 업데이트로 말없이 깨진다.
///
/// 노출면을 관절 6개로 좁혀 둔 덕에 가짜 구현이 몇 줄로 끝난다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md 구현 선택지 2
public protocol BodyPoseObservable: Sendable {
    /// 관절 하나. 관측에 없으면 `nil`이다.
    ///
    /// **신뢰도로 걸러내지 않는다.** 임계 판단은 `PoseFrame.point(_:minimumConfidence:)`가
    /// 프로파일 값으로 한다 — 여기서 한 번 더 걸러내면 같은 판단이 두 곳에
    /// 생기고, 둘이 어긋나면 트리거가 조용히 신호를 잃는다.
    func sample(for joint: PoseJoint) -> PoseJointSample?
}

extension BodyPoseObservable {
    /// 두 어깨 사이 거리. 사람을 고르는 기준이다 — 카메라에 가까울수록 크다.
    ///
    /// 한쪽 어깨라도 안 보이면 `nil`이다. 0을 돌려주면 "가장 작은 사람"으로
    /// 취급돼 선택에서 밀리기만 하지만, 전원이 `nil`인 경우와 구분되지 않는다.
    public func shoulderWidth(minimumConfidence: Double) -> Double? {
        guard let left = sample(for: .leftShoulder), left.confidence >= minimumConfidence,
              let right = sample(for: .rightShoulder), right.confidence >= minimumConfidence
        else { return nil }
        return Double(hypot(left.point.x - right.point.x, left.point.y - right.point.y))
    }
}

/// Vision 관측을 경계에 적합시킨다. 전달만 한다 — 여기에 판단을 두지 않는다.
extension HumanBodyPoseObservation: BodyPoseObservable {
    public func sample(for joint: PoseJoint) -> PoseJointSample? {
        guard let found = self.joint(for: joint.visionName) else { return nil }
        // `NormalizedPoint`는 좌하단 원점이다. 뒤집지 않는다 —
        // `PoseFrame`이 그 좌표계를 전제한다(동시성 6.7).
        return PoseJointSample(
            point: found.location.cgPoint,
            confidence: Double(found.confidence)
        )
    }
}

extension PoseJoint {
    /// Vision의 관절 이름. 19개 중 트리거가 쓰는 6개만 매핑한다.
    var visionName: HumanBodyPoseObservation.JointName {
        switch self {
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        }
    }
}
