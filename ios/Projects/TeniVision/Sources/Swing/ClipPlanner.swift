import Foundation

/// 스윙 후보를 겹치는 것끼리 묶어 **클립 한 구간**으로 만드는 상태 기계.
///
/// ## 왜 병합하는가
///
/// 재발화 간격은 0.8초인데 구간은 `preRoll` + `postRoll` = 4초다. 연속
/// 스윙에서는 **거의 항상 겹친다.** 후보마다 클립을 만들면 같은 프레임을
/// 여러 번 인코딩하고 랠리 한 번에 클립이 수십 개 생긴다.
///
/// `Clip.swings`가 배열인 이유가 이것이다 — 클립 하나에 스윙 여럿.
///
/// ## 왜 프레임이 플러시를 구동하는가
///
/// 구간의 끝은 **미래다**(`triggeredAt + postRoll`). 타이머로 닫으면
/// 테스트가 시간에 의존하고, [동시성 6.1](../../../../docs/02-설계/CONCURRENCY.md)이
/// "순서가 중요한 처리는 단일 Task"로 정한 경로에 타이머가 끼어든다.
/// 프레임 시각이 구간 끝을 지나면 닫는다 — 결정론적이다.
///
/// 근거: docs/07-기획/SPEC-0091-swing-clip-recording.md 구현 선택지 2·3
public struct ClipPlanner: Sendable {

    /// 클립 하나가 될 구간.
    public struct Segment: Sendable, Equatable {
        /// 꺼내야 할 시간 범위. 묶인 후보들의 합집합이다.
        public internal(set) var range: ClosedRange<TimeInterval>
        /// 이 구간에 묶인 스윙들. 들어온 순서, 즉 시간 순이다.
        public internal(set) var marks: [Mark]

        public init(range: ClosedRange<TimeInterval>, marks: [Mark]) {
            self.range = range
            self.marks = marks
        }
    }

    /// 구간 안의 스윙 하나. 아직 **세션 시계 기준 절대 시각**이다 —
    /// 클립 시작 기준 상대초로 바꾸는 것은 기록하는 쪽의 일이다.
    public struct Mark: Sendable, Equatable {
        public let triggeredAt: TimeInterval
        public let start: TimeInterval
        public let end: TimeInterval
        public let peakAngularVelocity: Double

        public init(_ candidate: SwingCandidate) {
            self.triggeredAt = candidate.triggeredAt
            self.start = candidate.range.lowerBound
            self.end = candidate.range.upperBound
            self.peakAngularVelocity = candidate.peakAngularVelocity
        }
    }

    private var open: Segment?

    public init() {}

    public var isOpen: Bool { open != nil }

    /// 열려 있는 구간의 범위. 닫혀 있으면 `nil`.
    ///
    /// 쓰기 세션이 **어디부터** 소급해 담을지 알아야 한다.
    public var openRange: ClosedRange<TimeInterval>? { open?.range }

    /// 후보를 받는다.
    ///
    /// 열린 구간과 겹치면 그 구간을 늘리고 `nil`을 돌려준다. 겹치지 않으면
    /// **열린 구간을 닫아 돌려주고** 새 구간을 연다.
    ///
    /// - Note: 후보가 겹치지 않을 만큼 떨어졌다면 그 사이에 들어온 프레임이
    ///   이미 `advance(to:)`로 구간을 닫았을 것이다. 즉 이 경로의 반환값은
    ///   **프레임이 끊긴 동안 후보가 들어온 경우**에만 나온다. 그래도 닫아
    ///   돌려주는 것이 맞다 — 버리면 스윙이 사라진다.
    public mutating func accept(_ candidate: SwingCandidate) -> Segment? {
        let mark = Mark(candidate)
        assert(
            candidate.range.lowerBound >= (open?.range.lowerBound ?? -.infinity),
            "후보가 시간을 거슬러 들어왔다"
        )

        guard var current = open else {
            open = Segment(range: candidate.range, marks: [mark])
            return nil
        }

        if candidate.range.lowerBound <= current.range.upperBound {
            current.range = current.range.lowerBound...max(
                current.range.upperBound, candidate.range.upperBound
            )
            current.marks.append(mark)
            open = current
            return nil
        }

        open = Segment(range: candidate.range, marks: [mark])
        return current
    }

    /// 프레임 시각을 알린다. 열린 구간의 끝을 **지났으면** 닫아 돌려준다.
    ///
    /// 경계는 포함하지 않는다 — 끝 시각의 프레임까지는 클립에 들어가야 한다.
    public mutating func advance(to seconds: TimeInterval) -> Segment? {
        guard let current = open, seconds > current.range.upperBound else { return nil }
        open = nil
        return current
    }

    /// 남은 구간을 닫는다. 세션 종료에서 부른다 — `postRoll`을 못 채운
    /// 구간도 버리지 않는다.
    public mutating func finish() -> Segment? {
        defer { open = nil }
        return open
    }
}
