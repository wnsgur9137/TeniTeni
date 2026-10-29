import Domain
import Foundation
import Testing
@testable import Presentation

/// 스크러버는 순수 계산이다. 플레이어도 화면도 없이 전수로 검증한다.
@Suite("리플레이 스크러버")
struct ReplayScrubberTests {

    @Test("구간 안의 시각을 0~1로 바꾼다")
    func 비율() {
        let scrubber = ReplayScrubber(start: 2, end: 4, impact: 3)

        #expect(scrubber.duration == 2)
        #expect(scrubber.fraction(at: 2) == 0)
        #expect(scrubber.fraction(at: 3) == 0.5)
        #expect(scrubber.fraction(at: 4) == 1)
        #expect(scrubber.impactFraction == 0.5)
    }

    @Test("구간 밖은 끝으로 조인다")
    func 범위_밖() {
        let scrubber = ReplayScrubber(start: 2, end: 4, impact: 3)

        #expect(scrubber.fraction(at: 0) == 0)
        #expect(scrubber.fraction(at: 100) == 1)
    }

    @Test("임팩트가 구간 밖이면 구간 안으로 조인다")
    func 임팩트_클램프() {
        // 검출이 임팩트를 구간 밖에 적을 수 있다. 조이지 않으면 마커가
        // 화면 밖으로 나간다.
        #expect(ReplayScrubber(start: 2, end: 4, impact: 9).impact == 4)
        #expect(ReplayScrubber(start: 2, end: 4, impact: -1).impact == 2)
        #expect(ReplayScrubber(start: 2, end: 4, impact: 9).impactFraction == 1)
        #expect(ReplayScrubber(start: 2, end: 4, impact: -1).impactFraction == 0)
    }

    @Test("길이 0 구간에서도 0으로 나누지 않는다")
    func 길이_0() {
        let scrubber = ReplayScrubber(start: 3, end: 3, impact: 3)

        #expect(scrubber.duration == 0)
        #expect(scrubber.fraction(at: 3) == 0)
        #expect(scrubber.fraction(at: 10) == 0)
        #expect(scrubber.impactFraction == 0)
        #expect(scrubber.seconds(atFraction: 1) == 3)
    }

    @Test("뒤집힌 구간을 바로잡는다")
    func 뒤집힘() {
        let scrubber = ReplayScrubber(start: 5, end: 1, impact: 3)

        #expect(scrubber.start == 1)
        #expect(scrubber.end == 5)
        #expect(scrubber.impact == 3)
    }

    @Test("0~1을 구간 안의 시각으로 되돌린다")
    func 역변환() {
        let scrubber = ReplayScrubber(start: 2, end: 4, impact: 3)

        #expect(scrubber.seconds(atFraction: 0) == 2)
        #expect(scrubber.seconds(atFraction: 0.5) == 3)
        #expect(scrubber.seconds(atFraction: 1) == 4)
        // 드래그가 뷰 밖으로 나가면 범위 밖 값이 온다.
        #expect(scrubber.seconds(atFraction: -0.3) == 2)
        #expect(scrubber.seconds(atFraction: 1.4) == 4)
    }

    @Test("Swing에서 바로 만든다")
    func 스윙에서() {
        let swing = Swing(startSeconds: 1, endSeconds: 3, impactSeconds: 2.5)
        let scrubber = ReplayScrubber(swing: swing)

        #expect(scrubber.start == 1)
        #expect(scrubber.end == 3)
        #expect(scrubber.impactFraction == 0.75)
    }
}
