import CoreGraphics
import Foundation
import Testing
@testable import TeniVision

/// 라켓 헤드 추정은 **정답이 없다.** 그래서 "맞다"를 검증하지 못하고,
/// 대신 식이 정의대로 계산되는지와 **못 믿는 입력을 걸러내는지**를 고정한다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md "라켓 궤적 — 추정식과 그 한계"
@Suite("라켓 헤드 추정")
struct RacketHeadTests {

    /// 16:9. 실제 클립의 종횡비다.
    private static let aspect = 16.0 / 9.0

    /// 어깨너비 0.2 norm-x, 즉 정사각 공간에서 0.2 × 16/9 = 0.3556.
    /// 그 폭이 0.40m이므로 1단위 = 1.125m.
    private static func input(
        wrist: CGPoint,
        mcp: CGPoint,
        wristConfidence: Double = 0.9,
        mcpConfidence: Double = 0.9,
        shoulderHalf: CGFloat = 0.1,
        aspect: Double = RacketHeadTests.aspect
    ) -> RacketHeadEstimator.Input {
        .init(
            wrist: PoseJointSample(point: wrist, confidence: wristConfidence),
            middleMCP: PoseJointSample(point: mcp, confidence: mcpConfidence),
            leftShoulder: CGPoint(x: 0.5 - shoulderHalf, y: 0.6),
            rightShoulder: CGPoint(x: 0.5 + shoulderHalf, y: 0.6),
            aspect: aspect
        )
    }

    // MARK: - 식

    /// 손이 **기대 길이 그대로** 보이면 단축이 1이고, 헤드는 그립 축을
    /// 라켓 길이(0.42m)만큼 늘인 자리에 온다.
    @Test("손이 기대 길이면 헤드는 그립 축으로 0.42m 거리에 온다")
    func 정상() throws {
        let aspect = Self.aspect
        // 정사각 공간에서 어깨너비
        let shoulder = 0.2 * aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / shoulder
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit
        let reachUnits = RacketHeadEstimator.gripToHeadMeters / metersPerUnit

        // 손을 **세로로** 둔다. 정사각 공간에서 y는 그대로이므로 길이가 바로 간다.
        let wrist = CGPoint(x: 0.5, y: 0.5)
        let mcp = CGPoint(x: 0.5, y: 0.5 + handUnits)

        let head = try #require(
            RacketHeadEstimator.estimate(
                Self.input(wrist: wrist, mcp: mcp), minimumConfidence: 0
            )
        )
        #expect(abs(head.confidence - 0.9) < 1e-9)
        #expect(abs(head.point.x - 0.5) < 1e-9)
        #expect(abs(Double(head.point.y - 0.5) - reachUnits) < 1e-9)
    }

    /// **종횡비 보정이 핵심이다.** 같은 실거리를 가로로 둔 손과 세로로 둔
    /// 손이 같은 뻗음을 내야 한다.
    ///
    /// 보정이 없으면 세로가 16:9 = 1.78배 짧게 나온다 — 팔로스루가 수직에
    /// 가까운 테니스 스윙에서 하필 가장 크게 틀리는 지점이다.
    @Test("가로 손과 세로 손이 같은 실거리를 뻗는다")
    func 종횡비_보정() throws {
        let aspect = Self.aspect
        let shoulder = 0.2 * aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / shoulder
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let vertical = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.5 + handUnits)
                ),
                minimumConfidence: 0
            )
        )
        // 가로로 같은 실거리를 두려면 정규화 x로는 aspect로 나눠야 한다.
        let horizontal = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5 + handUnits / aspect, y: 0.5)
                ),
                minimumConfidence: 0
            )
        )

        // 정사각 공간으로 되돌려 길이를 재면 둘이 같아야 한다.
        let vLen = hypot((vertical.point.x - 0.5) * aspect, vertical.point.y - 0.5)
        let hLen = hypot((horizontal.point.x - 0.5) * aspect, horizontal.point.y - 0.5)
        #expect(abs(vLen - hLen) < 1e-9)
        // 그리고 둘 다 단축 1이므로 신뢰도가 깎이지 않는다.
        #expect(abs(vertical.confidence - horizontal.confidence) < 1e-9)
    }

    // MARK: - 단축

    @Test("손이 절반으로 짧게 보이면 신뢰도가 절반이 된다")
    func 단축_절반() throws {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let head = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.5 + handUnits / 2)
                ),
                minimumConfidence: 0
            )
        )
        #expect(abs(head.confidence - 0.45) < 1e-9)
    }

    /// 손이 기대보다 **조금** 길게 보이는 것은 단축이 아니다(개인차·추정
    /// 오차). 1로 자른다 — 자르지 않으면 신뢰도가 1을 넘는다.
    @Test("손이 조금 길어도 단축은 1을 넘지 않는다")
    func 단축_상한() throws {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let head = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.5 + handUnits * 1.5)
                ),
                minimumConfidence: 0
            )
        )
        #expect(head.confidence <= 1)
        #expect(abs(head.confidence - 0.9) < 1e-9)
    }

    /// ⚠️ **측면 자세가 자를 망친다.** 몸이 돌면 투영된 어깨너비가 줄고
    /// 손 길이는 그만큼 줄지 않는다 — 그러면 비율이 1을 크게 넘는다.
    ///
    /// 상한 1로 깎아 버리면 그 실패가 **높은 신뢰도로 통과**하고, 손바닥
    /// 안에 찍힌 짧은 라켓이 그려진다. 테니스 준비 자세가 측면이므로
    /// 드문 경우가 아니다.
    @Test("자와 손이 2배 넘게 어긋나면 그리지 않는다")
    func 자_불신() {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        // 비율 3 — 어깨가 약 70° 돌아간 상황에 해당한다.
        #expect(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.5 + handUnits * 3)
                ),
                minimumConfidence: 0
            ) == nil
        )
        // 경계 바로 아래는 그린다.
        #expect(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(
                        x: 0.5,
                        y: 0.5 + handUnits * CGFloat(RacketHeadEstimator.maximumHandRatio * 0.99)
                    )
                ),
                minimumConfidence: 0
            ) != nil
        )
    }

    /// 어깨너비가 0에 가까우면 `metersPerUnit`이 폭발해 `reach`가 0이 되고,
    /// 동시에 비율이 커져 상한 1에 포화한다. **자 불신이 그것을 잡는다.**
    @Test("어깨가 거의 겹치면 그리지 않는다")
    func 어깨_거의_0() {
        #expect(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.55),
                    shoulderHalf: 0.0005
                ),
                minimumConfidence: 0
            ) == nil
        )
    }

    @Test("단축이 커서 신뢰도가 임계에 못 미치면 그 프레임은 nil이다")
    func 임계_미달() {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        // 손이 기대의 10%로 보인다 → 0.9 × 0.1 = 0.09
        let head = RacketHeadEstimator.estimate(
            Self.input(
                wrist: CGPoint(x: 0.5, y: 0.5),
                mcp: CGPoint(x: 0.5, y: 0.5 + handUnits * 0.1)
            ),
            minimumConfidence: 0.3
        )
        #expect(head == nil)
    }

    @Test("신뢰도는 두 관절 중 낮은 쪽을 쓴다")
    func 낮은_쪽() throws {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let head = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.5 + handUnits),
                    wristConfidence: 0.8,
                    mcpConfidence: 0.4
                ),
                minimumConfidence: 0
            )
        )
        #expect(abs(head.confidence - 0.4) < 1e-9)
    }

    // MARK: - 못 믿는 입력

    @Test("손목과 MCP가 같은 점이면 방향이 없으므로 nil이다")
    func 방향_없음() {
        let same = CGPoint(x: 0.5, y: 0.5)
        #expect(
            RacketHeadEstimator.estimate(
                Self.input(wrist: same, mcp: same), minimumConfidence: 0
            ) == nil
        )
    }

    @Test("두 어깨가 같은 점이면 자가 없으므로 nil이다")
    func 어깨_폭_0() {
        #expect(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.5),
                    mcp: CGPoint(x: 0.5, y: 0.6),
                    shoulderHalf: 0
                ),
                minimumConfidence: 0
            ) == nil
        )
    }

    @Test("종횡비가 0이나 음수면 nil이다")
    func 종횡비_불량() {
        for aspect in [0.0, -1.0] {
            #expect(
                RacketHeadEstimator.estimate(
                    Self.input(
                        wrist: CGPoint(x: 0.5, y: 0.5),
                        mcp: CGPoint(x: 0.5, y: 0.6),
                        aspect: aspect
                    ),
                    minimumConfidence: 0
                ) == nil
            )
        }
    }

    /// 화면 밖으로 나가도 **자르지 않는다.** 자르면 궤적이 가장자리에 붙어
    /// 거짓된 직선이 생긴다.
    @Test("헤드가 0~1을 벗어나도 그대로 낸다")
    func 화면_밖() throws {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let head = try #require(
            RacketHeadEstimator.estimate(
                Self.input(
                    wrist: CGPoint(x: 0.5, y: 0.95),
                    mcp: CGPoint(x: 0.5, y: 0.95 + handUnits)
                ),
                minimumConfidence: 0
            )
        )
        #expect(head.point.y > 1)
    }
}
