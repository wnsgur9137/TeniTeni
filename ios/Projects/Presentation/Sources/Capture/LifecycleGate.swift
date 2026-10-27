/// 화면 단계 전이를 **동기로** 기록한다.
///
/// ## 왜 값으로 빼는가
///
/// `scenePhase`는 `inactive → active → background`를 한 틱에 몰아서 준다.
/// 그런데 재개는 **비동기**(`await start()`)이고 중단은 **동기**다. 화면이
/// `Task { await controller.resume() }`로 재개를 띄우면 그 본문이 실행되기
/// 전에 `suspend()`가 끝나버리고, 뒤늦게 깨어난 재개가 세션을 다시 켠다 —
/// **백그라운드에서 카메라가 도는 상태**가 남는다
/// ([#82](https://github.com/wnsgur9137/TeniTeni/issues/82)).
///
/// 이 판정은 실기기가 필요 없다. 단계가 어떤 순서로 와도 결과가 하나로
/// 정해지는지 전수로 확인할 수 있으므로 값으로 뺀다 — `CaptureInterruption`과
/// `SystemPressureResponse`와 같은 수법이다.
///
/// ## 왜 불리언 하나로는 안 되는가
///
/// `wantsRunning`만 두면 `active → background → active`가 연달아 올 때
/// **첫 재개가 두 번째 전이의 허가로 통과한다.** 세션을 두 번 켜는 것은
/// 무해해 보이지만 그 뒤에 붙은 분석 세우기가 겹쳐 돌아 세대 토큰이 꼬인다.
/// 그래서 전이마다 세대를 늘리고, 재개는 **자기 세대**만 들고 간다.
struct LifecycleGate: Equatable, Sendable {

    /// 화면이 마지막으로 원한 상태.
    private(set) var wantsRunning = false

    /// 전이마다 늘어난다. 비행 중인 재개가 자기 세대를 들고 돌아와 확인한다.
    private(set) var generation = 0

    /// 포그라운드 진입. 돌려받은 세대를 비동기 재개가 들고 간다.
    mutating func enterForeground() -> Int {
        wantsRunning = true
        generation += 1
        return generation
    }

    /// 백그라운드·비활성 진입. 비행 중인 재개는 이 호출로 무효가 된다.
    mutating func leaveForeground() {
        wantsRunning = false
        generation += 1
    }

    /// 이 세대의 재개가 **아직 유효한가.**
    ///
    /// 중간에 중단이 끼어들었거나 더 새로운 재개가 떴으면 거짓이다.
    func admits(_ generation: Int) -> Bool {
        wantsRunning && generation == self.generation
    }
}
