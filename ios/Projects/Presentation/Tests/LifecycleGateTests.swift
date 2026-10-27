import Testing
@testable import Presentation

/// `scenePhase`가 어떤 순서로 와도 결과가 하나로 정해지는지 전수로 본다.
/// 실기기도 카메라도 필요 없다 — 그래서 값으로 빼냈다(#82).
@Suite("생명주기 게이트")
struct LifecycleGateTests {

    @Test("처음에는 아무 재개도 허가하지 않는다")
    func 초기() {
        let gate = LifecycleGate()
        #expect(gate.wantsRunning == false)
        #expect(gate.admits(0) == false, "세대 0을 들고 와도 의도가 없으면 거짓이다")
    }

    @Test("포그라운드 진입이 발급한 세대는 허가된다")
    func 정상_재개() {
        var gate = LifecycleGate()
        let generation = gate.enterForeground()
        #expect(gate.wantsRunning)
        #expect(gate.admits(generation))
    }

    /// 이 PR이 고치는 바로 그 순서다. 재개가 중단 뒤에 깨어나도
    /// 세션을 다시 켜지 못해야 한다.
    @Test("inactive → active → background 순서면 그 재개는 버려진다")
    func 중단이_끼어든다() {
        var gate = LifecycleGate()
        gate.leaveForeground()                      // inactive
        let generation = gate.enterForeground()     // active — 여기서 Task가 뜬다
        gate.leaveForeground()                      // background — Task가 깨기 전에

        #expect(gate.wantsRunning == false)
        #expect(gate.admits(generation) == false, "백그라운드에서 세션을 켜면 안 된다")
    }

    /// 불리언 하나로는 막지 못하는 순서다. 두 번째 진입의 허가로
    /// 첫 재개가 통과하면 분석 세우기가 겹쳐 돈다.
    @Test("더 새로운 재개가 뜨면 이전 재개는 버려진다")
    func 재개가_겹친다() {
        var gate = LifecycleGate()
        let first = gate.enterForeground()
        gate.leaveForeground()
        let second = gate.enterForeground()

        #expect(gate.wantsRunning)
        #expect(gate.admits(first) == false)
        #expect(gate.admits(second))
    }

    @Test("연달아 들어온 포그라운드도 마지막 것만 통과한다")
    func 중복_진입() {
        var gate = LifecycleGate()
        let first = gate.enterForeground()
        let second = gate.enterForeground()

        #expect(gate.admits(first) == false)
        #expect(gate.admits(second))
    }

    @Test("중단 뒤 재진입은 새 세대로 허가된다")
    func 복귀() {
        var gate = LifecycleGate()
        _ = gate.enterForeground()
        gate.leaveForeground()
        let generation = gate.enterForeground()

        #expect(gate.admits(generation))
    }

    /// 세대가 재사용되면 버려야 할 재개가 통과한다.
    @Test("세대는 전이마다 늘어나고 되돌아가지 않는다")
    func 세대_단조() {
        var gate = LifecycleGate()
        var seen: [Int] = [gate.generation]
        for step in 0..<6 {
            if step.isMultiple(of: 2) {
                seen.append(gate.enterForeground())
            } else {
                gate.leaveForeground()
                seen.append(gate.generation)
            }
        }
        #expect(seen == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test("중단을 거듭 불러도 의도는 내려간 채 남는다")
    func 중복_중단() {
        var gate = LifecycleGate()
        let generation = gate.enterForeground()
        gate.leaveForeground()
        gate.leaveForeground()

        #expect(gate.wantsRunning == false)
        #expect(gate.admits(generation) == false)
    }
}
