import Domain
import Foundation

/// 스윙 구간을 0~1로 재는 순수 계산.
///
/// **클립 전체가 아니라 스윙 구간만 잰다.** 구간 찾기는 검출이 이미 했으므로
/// 긴 타임라인을 훑을 필요가 없다 — Onform의 매크로 스크러버에 대응하는 것은
/// 우리에게 "앞뒤 스윙 넘기기"다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 4.
public struct ReplayScrubber: Equatable, Sendable {

    public let start: TimeInterval
    public let end: TimeInterval
    /// **구간 안으로 조인 값.** 검출이 임팩트를 구간 밖에 적어도 스크러버가
    /// 화면 밖으로 나가지 않는다.
    public let impact: TimeInterval

    public init(start: TimeInterval, end: TimeInterval, impact: TimeInterval) {
        // 뒤집혀 들어오면 바로잡는다. 길이 0은 그대로 둔다 — 아래 계산이
        // 0으로 나누지 않는다.
        let lower = min(start, end)
        let upper = max(start, end)
        self.start = lower
        self.end = upper
        self.impact = min(max(impact, lower), upper)
    }

    public init(swing: Swing) {
        self.init(
            start: swing.startSeconds,
            end: swing.endSeconds,
            impact: swing.impactSeconds
        )
    }

    public var duration: TimeInterval { end - start }

    /// 구간 안의 시각을 0~1로. 구간 밖은 끝으로 조인다.
    ///
    /// 길이가 0이면 0을 준다 — 길이 0 구간에서는 어디에 있든 시작이다.
    public func fraction(at seconds: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        let offset = seconds - start
        return min(max(offset / duration, 0), 1)
    }

    public var impactFraction: Double { fraction(at: impact) }

    /// 0~1을 구간 안의 시각으로. 범위 밖 입력은 조인다.
    public func seconds(atFraction fraction: Double) -> TimeInterval {
        let clamped = min(max(fraction, 0), 1)
        return start + duration * clamped
    }
}
