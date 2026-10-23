import Foundation
import Testing
@testable import TeniVision

@Suite("클립 구간 계획")
struct ClipPlannerTests {

    @Test("후보 하나는 구간을 열고 아직 닫지 않는다")
    func 단일_후보() {
        var planner = ClipPlanner()
        #expect(planner.accept(ClipFixture.candidate(triggeredAt: 3.0)) == nil)
        #expect(planner.isOpen)
        #expect(planner.openRange == 1.0...5.0)
    }

    @Test("구간 끝의 프레임까지는 클립에 들어간다")
    func 경계_포함() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0))
        #expect(planner.advance(to: 5.0) == nil)
        #expect(planner.isOpen)
    }

    @Test("끝을 지난 프레임이 구간을 닫는다")
    func 지나면_닫힌다() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0))
        let closed = planner.advance(to: 5.001)
        #expect(closed?.range == 1.0...5.0)
        #expect(closed?.marks.count == 1)
        #expect(planner.isOpen == false)
    }

    @Test("겹치는 후보는 한 구간으로 묶인다")
    func 병합() {
        var planner = ClipPlanner()
        #expect(planner.accept(ClipFixture.candidate(triggeredAt: 3.0)) == nil)
        // 1.0...5.0 과 2.0...6.0 은 겹친다
        #expect(planner.accept(ClipFixture.candidate(triggeredAt: 4.0)) == nil)
        #expect(planner.openRange == 1.0...6.0)

        let closed = planner.advance(to: 6.001)
        #expect(closed?.marks.count == 2)
        #expect(closed?.marks.map(\.triggeredAt) == [3.0, 4.0])
    }

    @Test("맞닿은 후보도 겹친 것으로 본다")
    func 맞닿음() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0))
        // 하한 5.0 == 상한 5.0
        #expect(planner.accept(ClipFixture.candidate(triggeredAt: 7.0)) == nil)
        #expect(planner.openRange == 1.0...9.0)
    }

    @Test("떨어진 후보는 앞 구간을 닫고 새로 연다")
    func 분리() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0))
        // 하한 8.0 > 상한 5.0
        let closed = planner.accept(ClipFixture.candidate(triggeredAt: 10.0))
        #expect(closed?.range == 1.0...5.0)
        #expect(closed?.marks.count == 1)
        #expect(planner.openRange == 8.0...12.0)
    }

    @Test("finish가 남은 구간을 돌려준다")
    func 종료() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0))
        let last = planner.finish()
        #expect(last?.range == 1.0...5.0)
        #expect(planner.finish() == nil)
    }

    @Test("열린 구간이 없으면 아무것도 닫히지 않는다")
    func 빈_상태() {
        var planner = ClipPlanner()
        #expect(planner.advance(to: 100) == nil)
        #expect(planner.finish() == nil)
    }

    @Test("마크는 후보의 구간과 피크를 그대로 들고 있다")
    func 마크_내용() {
        var planner = ClipPlanner()
        _ = planner.accept(ClipFixture.candidate(triggeredAt: 3.0, peak: 9.5))
        let mark = planner.finish()?.marks.first
        #expect(mark?.triggeredAt == 3.0)
        #expect(mark?.start == 1.0)
        #expect(mark?.end == 5.0)
        #expect(mark?.peakAngularVelocity == 9.5)
    }
}
