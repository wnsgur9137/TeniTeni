import Foundation

/// 리플레이 배속.
///
/// 하한이 0.1×가 아니라 **0.125×**인 이유: 1/8이므로 120fps 클립이 정확히
/// 15fps로 보이고, 0.25×의 정확히 절반이다. Onform의 하한과도 같다
/// (docs/08-레퍼런스/Onform.md).
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 2.
public enum PlaybackSpeed: Double, CaseIterable, Equatable, Sendable {
    case eighth = 0.125
    case quarter = 0.25
    case half = 0.5
    case normal = 1

    /// 기본값은 0.25×다. 리플레이를 여는 이유가 느리게 보는 것이다.
    public static let standard: PlaybackSpeed = .quarter

    public var label: String {
        switch self {
        case .eighth: "0.125×"
        case .quarter: "0.25×"
        case .half: "0.5×"
        case .normal: "1×"
        }
    }

    public var isSlowMotion: Bool { rawValue < 1 }
}
