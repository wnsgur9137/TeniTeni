import Foundation

/// 리플레이에서 영상 위에 켜는 레이어. **한 번에 하나만** 켠다.
///
/// ## 왜 배타적인가
///
/// 독립 토글 4개는 조합 16가지이고 대부분은 시각적 소음이다. 리플레이는
/// 폰 앞에서 보는 화면이므로 탭 한 번의 비용이 작다 — 6m 제약을 받는 촬영
/// 화면과 다르다.
///
/// ## 왜 둘뿐인가
///
/// 볼 궤적은 0-C 게이트, 라인은 1-F 호모그래피가 선행이다. **열거형에
/// 자리를 비워 두지 않는다** — 없는 case를 두면 UI가 그릴 수 없는 모드를
/// 그리게 되고, `switch`가 "아직 안 됨"으로 분기하는 죽은 코드가 생긴다.
/// 선행이 풀리면 case를 더한다.
///
/// 근거: docs/05-결정/adr/ADR-0006-replay-overlay-layers.md ·
/// docs/07-기획/SPEC-0121-replay-overlay.md
public enum OverlayLayer: String, Sendable, Hashable, CaseIterable, Codable {
    case off
    case skeleton
    case racket

    /// 화면에 적는 이름.
    public var title: String {
        switch self {
        case .off: "끔"
        case .skeleton: "스켈레톤"
        case .racket: "라켓 궤적"
        }
    }

    /// 사이드카가 있어야 그릴 수 있는가.
    ///
    /// `off`만 아니면 전부 필요하다. 지금은 자명하지만 레이어가 늘면
    /// (라인은 호모그래피만 있으면 된다) 갈린다.
    public var needsSidecar: Bool { self != .off }
}
