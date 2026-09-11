import Foundation

/// 조건 하나의 검출 성능.
///
/// 우리 "검출률"은 표준의 **recall**이고 "오검출률"은 **1 − precision**이다.
/// 게이트는 recall로만 판정하지만(프로토콜 5.5) 둘 다 낸다 — recall만 보면
/// 헛검출 많은 설정이 "최적"으로 뽑힌다.
/// 근거: docs/08-레퍼런스/ml/DetectionMetrics.md 2절
public struct DetectionMetrics: Codable, Sendable {

    /// 매칭된 타구 수
    public let truePositives: Int
    /// 실제 타구와 무관하게 검출된 궤적 수
    public let falsePositives: Int
    /// 놓친 타구 수
    public let falseNegatives: Int

    public init(truePositives: Int, falsePositives: Int, falseNegatives: Int) {
        self.truePositives = truePositives
        self.falsePositives = falsePositives
        self.falseNegatives = falseNegatives
    }

    /// 검출한 것 중 맞은 비율. 낮으면 **헛것을 많이 잡는다**.
    public var precision: Double {
        let denominator = truePositives + falsePositives
        guard denominator > 0 else { return 0 }
        return Double(truePositives) / Double(denominator)
    }

    /// 실제 중 잡은 비율. **프로토콜 5.5의 "검출률"이 이것이다.**
    public var recall: Double {
        let denominator = truePositives + falseNegatives
        guard denominator > 0 else { return 0 }
        return Double(truePositives) / Double(denominator)
    }

    /// precision과 recall의 조화평균
    public var f1: Double {
        let sum = precision + recall
        guard sum > 0 else { return 0 }
        return 2 * precision * recall / sum
    }

    /// TN이 없으므로 accuracy와 FPR은 정의되지 않는다.
    /// "타구가 아닌 프레임"을 세지 않기 때문이다.

    // MARK: 게이트 판정

    /// 프로토콜 5.5의 판정. **recall 기준이다** — 기준을 바꾸지 않는다.
    public enum Verdict: String, Codable, Sendable {
        case pass        // ≥ 70 %
        case tune        // 50 ~ 70 %
        case redesign    // < 50 %

        public var label: String {
            switch self {
            case .pass: "✅ 통과"
            case .tune: "⚠️ 튜닝 필요"
            case .redesign: "❌ 재설계"
            }
        }

        public var action: String {
            switch self {
            case .pass: "Phase 1 진행"
            case .tune: "파라미터·노출·거리 튜닝 후 재측정"
            case .redesign: "접근 재설계 — D-20 서버 TrackNet 또는 궤적 기능 v1 제외"
            }
        }
    }

    public var verdict: Verdict {
        if recall >= 0.70 { return .pass }
        if recall >= 0.50 { return .tune }
        return .redesign
    }

    /// recall이 높아도 precision이 낮으면 실사용이 불가능하다.
    /// 게이트 기준에는 없지만 드러내야 한다.
    public static let precisionWarningThreshold = 0.50

    public var precisionIsLow: Bool {
        truePositives + falsePositives > 0 && precision < Self.precisionWarningThreshold
    }
}
