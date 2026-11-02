import CoreGraphics
import Foundation

/// Vision이 내는 신체 관절 **19개 전부**.
///
/// ## 왜 6개에서 19개로 넓혔나
///
/// 트리거는 6개(`trigger`)만 쓴다. 스켈레톤 오버레이는 전부 필요하다
/// (#121). 열거형을 둘로 나누면 사이드카가 어느 쪽을 담는지가 호출부마다
/// 갈리므로 **하나로 두고 쓰는 쪽에서 고른다.**
///
/// ⚠️ **`allCases`를 라이브 경로에 쓰지 마라.** 프레임마다 19개를 뽑으면
/// 트리거가 쓰지도 않는 13개의 비용을 실시간 예산에서 낸다.
/// `PoseFrameAdapter.frame(from:at:)`이 `trigger`만 뽑는 이유다.
///
/// 근거: docs/07-기획/SPEC-0085-swing-trigger.md ·
/// docs/07-기획/SPEC-0121-replay-overlay.md 선택지 5
public enum PoseJoint: String, Sendable, Hashable, CaseIterable, Codable {
    case nose
    case neck
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case root
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle

    /// 스윙 트리거가 읽는 6개.
    ///
    /// **순서를 바꾸지 마라.** 테스트가 이 순서로 가짜 관측을 꽂는다.
    public static let trigger: [PoseJoint] = [
        .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftWrist, .rightWrist,
    ]
}

/// 사이드카 JSON에서 관절 딕셔너리가 **객체**가 되게 한다.
///
/// 이 선언이 없으면 `[PoseJoint: _]`는 `[키, 값, 키, 값, ...]` 배열로
/// 인코딩된다 — 왕복은 되지만 **사람이 열어 읽을 수 없다.** 사이드카를
/// JSON으로 고른 이유의 절반이 그것이다(SPEC-0121 선택지 1).
extension PoseJoint: CodingKeyRepresentable {}

/// 스켈레톤에서 선으로 이을 관절 쌍.
///
/// 렌더가 자기 목록을 들면 화면마다 다른 뼈대가 생긴다. **한 곳에 둔다.**
///
/// 얼굴(눈·귀·코)은 잇지 않는다 — 테니스 폼에서 읽을 것이 없고, 선을
/// 그으면 작은 화면에서 머리가 덩어리로 뭉친다.
public enum SkeletonBone {
    public static let all: [(PoseJoint, PoseJoint)] = [
        (.neck, .nose),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    /// 라켓을 든 팔의 뼈. 시선 유도를 위해 다른 색으로 그린다
    /// (`overlay/racket-arm`, DESIGN-SYSTEM 11.2).
    public static func racketArm(_ side: RacketSide) -> [(PoseJoint, PoseJoint)] {
        switch side {
        case .left: [(.leftShoulder, .leftElbow), (.leftElbow, .leftWrist)]
        case .right: [(.rightShoulder, .rightElbow), (.rightElbow, .rightWrist)]
        }
    }
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
public struct PoseJointSample: Sendable, Equatable, Codable {
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
