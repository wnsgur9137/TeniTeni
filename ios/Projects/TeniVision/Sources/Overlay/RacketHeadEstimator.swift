import CoreGraphics
import Foundation

/// 라켓 헤드 하나의 추정 결과.
public struct RacketHead: Sendable, Equatable, Codable {
    /// Vision 정규화 좌표(좌하단 원점). 화면 변환은 `RenderTransform`이 한다.
    public let point: CGPoint
    /// 0~1. **단축(foreshortening)이 곱해진 값이다** — 손이 카메라 쪽을
    /// 향하면 낮아진다.
    public let confidence: Double

    public init(point: CGPoint, confidence: Double) {
        self.point = point
        self.confidence = confidence
    }
}

/// 라켓 헤드를 손 관절에서 추정한다.
///
/// ## 이것은 측정이 아니다
///
/// **라켓을 찾아주는 API가 없다.** 손의 그립 축을 라켓 길이만큼 늘인다.
/// 깊이를 모르므로 단축을 보정할 수 없고, 대신 **의심한다** — 손 자체가
/// 같이 단축되므로 손이 기대보다 짧게 보이면 라켓도 그만큼 단축됐다.
///
/// 정답이 없어 정확도를 수치로 판정할 방법이 없다. 화면에 "추정"이라고
/// 적는 것이 이 타입의 한계에 대한 유일한 정직한 대응이다.
///
/// ## 왜 값 타입인가
///
/// 관측도 시간도 들지 않는 순수 기하다. 그래서 **전수 테스트가 된다** —
/// 이 작업에서 실기기 없이 고정할 수 있는 거의 유일한 부분이다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md "라켓 궤적 — 추정식과 그 한계"
public enum RacketHeadEstimator {

    /// 성인 평균 양어깨 너비. **개인차를 무시한다.**
    public static let shoulderMeters: Double = 0.40
    /// 그립(손 위치)에서 헤드 중심까지. ITF 최대 전장 0.685m, 손이 버트에서
    /// 약 0.10m 위, 헤드 중심이 버트에서 약 0.52m.
    public static let gripToHeadMeters: Double = 0.42
    /// 손목에서 `middleMCP`까지. 단축을 재는 자다.
    public static let handMeters: Double = 0.10

    /// 추정에 필요한 입력 전부.
    ///
    /// 구조체로 묶는 이유: 인자가 다섯이고 **둘은 좌표계가 다르다**(손/신체).
    /// 호출부에서 섞이면 조용히 틀린다.
    public struct Input: Sendable, Equatable {
        /// 손 관측의 손목. **신체 관측의 손목이 아니다** —
        /// `middleMCP`와 같은 추정에서 나와야 손 길이가 뜻을 가진다.
        public let wrist: PoseJointSample
        /// 손 관측의 가운뎃손가락 중수골.
        public let middleMCP: PoseJointSample
        /// 신체 관측의 두 어깨. 거리를 자로 쓴다.
        public let leftShoulder: CGPoint
        public let rightShoulder: CGPoint
        /// 영상의 `픽셀 가로 / 픽셀 세로`. **1을 넣으면 안 된다** — 아래
        /// "왜 종횡비가 필요한가"를 보라.
        public let aspect: Double

        public init(
            wrist: PoseJointSample,
            middleMCP: PoseJointSample,
            leftShoulder: CGPoint,
            rightShoulder: CGPoint,
            aspect: Double
        ) {
            self.wrist = wrist
            self.middleMCP = middleMCP
            self.leftShoulder = leftShoulder
            self.rightShoulder = rightShoulder
            self.aspect = aspect
        }
    }

    /// 헤드 위치와 신뢰도. 임계 미달이면 `nil`이다 — **그 프레임은 선을 끊는다.**
    ///
    /// ## 왜 종횡비가 필요한가
    ///
    /// 정규화 좌표는 두 축이 모두 0~1이지만 **실거리로는 등방이 아니다.**
    /// 1920×1080에서 같은 0.4m가 가로로는 0.208 norm-x, 세로로는 0.370 norm-y다
    /// (16:9 = 1.78배).
    ///
    /// 어깨너비는 거의 가로이므로 그 값으로 만든 스케일을 그대로 쓰면
    /// **세로 방향 라켓이 1.78배 짧게** 추정된다. 팔로스루가 수직에 가까운
    /// 테니스 스윙에서 하필 가장 크게 틀린다.
    ///
    /// 그래서 **x에 종횡비를 곱한 공간**(단위가 영상 세로 기준인 정사각 공간)에서
    /// 방향과 길이를 계산하고, 마지막에 되돌린다.
    ///
    /// > 기획서의 식은 이 보정을 빠뜨렸다. 구현에서 더했다.
    public static func estimate(_ input: Input, minimumConfidence: Double) -> RacketHead? {
        let aspect = input.aspect
        guard aspect.isFinite, aspect > 0 else { return nil }

        // 정사각 공간으로. 이 공간에서만 거리가 실거리에 비례한다.
        func square(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }

        let wrist = square(input.wrist.point)
        let mcp = square(input.middleMCP.point)
        let left = square(input.leftShoulder)
        let right = square(input.rightShoulder)

        let shoulderWidth = Double(hypot(left.x - right.x, left.y - right.y))
        guard shoulderWidth > 0 else { return nil }

        // 정사각 공간 1단위가 몇 미터인가.
        let metersPerUnit = shoulderMeters / shoulderWidth
        guard metersPerUnit.isFinite, metersPerUnit > 0 else { return nil }

        let gripVector = CGPoint(x: mcp.x - wrist.x, y: mcp.y - wrist.y)
        let handLength = Double(hypot(gripVector.x, gripVector.y))
        // 손목과 MCP가 같은 점이면 방향이 없다. 0으로 나누지 않는다 —
        // 나누면 NaN이 좌표로 흘러 Canvas가 아무것도 그리지 않는다.
        guard handLength > 0 else { return nil }

        // 손이 기대보다 짧게 보이면 라켓도 그만큼 단축됐다.
        let expectedHand = handMeters / metersPerUnit
        guard expectedHand > 0 else { return nil }
        let foreshorten = min(max(handLength / expectedHand, 0), 1)

        let confidence = min(input.wrist.confidence, input.middleMCP.confidence) * foreshorten
        guard confidence >= minimumConfidence else { return nil }

        let reach = gripToHeadMeters / metersPerUnit
        let unit = CGPoint(x: gripVector.x / handLength, y: gripVector.y / handLength)
        let headSquare = CGPoint(x: wrist.x + unit.x * reach, y: wrist.y + unit.y * reach)

        // 정규화 좌표로 되돌린다. 화면 밖으로 나가도 자르지 않는다 —
        // 자르면 궤적이 화면 가장자리에 붙어 **거짓된 직선**이 생긴다.
        return RacketHead(
            point: CGPoint(x: headSquare.x / aspect, y: headSquare.y),
            confidence: confidence
        )
    }
}
