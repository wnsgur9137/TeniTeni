import Foundation

/// 공이 어디서 오는가. **어느 룰이 유효한지**를 결정한다.
///
/// 왕복 빈도는 여기서 도출된다 — 따로 묻지 않는다.
/// 근거: docs/06-디자인/IA-FLOW.md 10.4
public enum CaptureSituation: String, Sendable, Codable, CaseIterable {
    case ballMachine
    case wall
    case rally
    case match
    case lesson

    public var label: String {
        switch self {
        case .ballMachine: "볼머신"
        case .wall: "벽치기"
        case .rally: "랠리"
        case .match: "시합"
        case .lesson: "레슨"
        }
    }

    /// 관찰 대상을 고를 수 있는가. **시합에서만** 갈린다 —
    /// 다른 상황에는 판정할 라인이 없다.
    ///
    /// 배치는 여기서 나오지 않는다. 상황이 아니라 **관찰 대상**이 정한다 —
    /// `ObservationTarget.placement`.
    public var allowsLineCall: Bool { self == .match }

    /// 이 상황에서 무효화할 룰. 1-D의 룰 엔진이 읽는다.
    ///
    /// 벽치기는 벽이 가까워 팔로스루가 **구조적으로** 잘린다. 그것을
    /// 모르면 매 스윙마다 "팔로스루가 부족합니다"를 내고, 사용자는
    /// 앱이 맥락을 모른다고 판단한다.
    public var disabledRules: Set<String> {
        switch self {
        case .wall: ["followThroughAngle"]
        default: []
        }
    }
}

/// 앱이 무엇을 보는가. **삼각대 배치**를 결정한다.
/// 근거: docs/05-결정/adr/ADR-0004-line-call-mode.md
public enum ObservationTarget: String, Sendable, Codable, CaseIterable {
    case swing
    case lineCall

    public var label: String {
        switch self {
        case .swing: "내 스윙"
        case .lineCall: "라인 판정"
        }
    }

    public var placement: String {
        switch self {
        case .swing: "코트 옆 6m, 허리 높이"
        case .lineCall: "판정할 라인의 연장선"
        }
    }
}
