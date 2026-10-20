import Domain

/// 촬영 직전 화면이 보여줄 안내. **관찰 대상이 정한다** — 배치가 다르면
/// 같은 가이드를 쓸 수 없다.
///
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.6 · 5.7
public struct FramingGuidance: Equatable, Sendable {

    /// 프리뷰 위에 그릴 구도 가이드.
    public enum Frame: Equatable, Sendable {
        /// 인체 실루엣 밴드 — 선수가 프레임 높이의 35~45%를 차지해야 한다
        case body
        /// 라인 밴드 — 판정할 라인이 화면을 가로질러야 한다
        case line
    }

    public let headline: String
    public let placement: String
    public let frame: Frame

    public static func make(for target: ObservationTarget) -> Self {
        switch target {
        case .swing:
            // 배치 문구는 Domain이 들고 있는 것을 쓴다. 두 벌로 두면 갈라진다.
            Self(
                headline: "선수가 네모 안에 들어오게 두세요",
                placement: "\(target.placement) · 코트 장축에 수직",
                frame: .body
            )
        case .lineCall:
            Self(
                headline: "라인이 화면을 가로지르게 두세요",
                placement: "\(target.placement) · 라인 전체가 들어오게",
                frame: .line
            )
        }
    }
}
