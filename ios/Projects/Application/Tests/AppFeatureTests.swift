import AVFoundation
import ComposableArchitecture
import Domain
import Foundation
import Presentation
import Testing
import UIKit
@testable import Application

/// 테스트용 저장소. 실제 `UserDefaults`를 건드리면 테스트끼리 간섭한다.
private final class InMemoryRepository: UserPreferencesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: UserPreferences

    init(_ initial: UserPreferences = UserPreferences()) { stored = initial }

    func load() -> UserPreferences {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ preferences: UserPreferences) {
        lock.lock(); defer { lock.unlock() }
        stored = preferences
    }
}

@Suite("앱 루트")
@MainActor
struct AppFeatureTests {

    // MARK: 온보딩

    @Test("주 사용 손이 없으면 온보딩을 마치지 못한다")
    func 손_없이는_완료_불가() async {
        let repo = InMemoryRepository()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature(repository: repo)
        }

        // 고르지 않고 "다음"을 눌러도 아무 일도 일어나지 않는다.
        await store.send(.onboarding(.finishTapped))

        #expect(repo.load().handedness == nil, "저장되면 안 된다")
        #expect(store.state.hasCompletedOnboarding == false)
    }

    @Test("주 사용 손을 고르면 온보딩이 끝나고 저장된다")
    func 손_고르면_완료() async {
        let repo = InMemoryRepository()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature(repository: repo)
        }

        await store.send(.onboarding(.startTapped)) {
            $0.onboarding.step = .handedness
        }
        await store.send(.onboarding(.handednessSelected(.left))) {
            $0.onboarding.handedness = .left
        }
        await store.send(.onboarding(.finishTapped))
        await store.receive(.onboarding(.delegate(.completed(.left)))) {
            $0.preferences.handedness = .left
        }

        #expect(store.state.hasCompletedOnboarding)
        #expect(repo.load().handedness == .left, "재실행 시 온보딩을 건너뛰려면 저장돼야 한다")
    }

    @Test("저장된 설정이 있으면 온보딩을 건너뛴다")
    func 재실행() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right, lastSituation: .wall))
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature(repository: repo)
        }

        await store.send(.appeared) {
            $0.preferences = UserPreferences(handedness: .right, lastSituation: .wall)
            $0.home = HomeFeature.State(situation: .wall, observable: .swing)
        }
        #expect(store.state.hasCompletedOnboarding)
    }

    // MARK: 촬영 상황

    @Test("상황을 고르면 저장된다 — 다음 실행에서 미리 골라두려면")
    func 상황_저장() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.situationSelected(.lesson))) {
            $0.home.situation = .lesson
        }
        await store.receive(.home(.delegate(.selectionChanged(.lesson, .swing)))) {
            $0.preferences.lastSituation = .lesson
        }
        #expect(repo.load().lastSituation == .lesson)
    }

    @Test("시합이 아니면 라인 판정을 고를 수 없다")
    func 라인판정은_시합만() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        // 볼머신 상태에서 라인 판정을 시도해도 무시된다.
        await store.send(.home(.observableSelected(.lineCall)))
        #expect(store.state.home.observable == .swing)
    }

    @Test("시합에서 라인 판정을 고른 뒤 다른 상황으로 가면 초기화된다")
    func 상황_바꾸면_관찰대상_초기화() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.situationSelected(.match))) { $0.home.situation = .match }
        await store.receive(.home(.delegate(.selectionChanged(.match, .swing)))) {
            $0.preferences.lastSituation = .match
        }
        await store.send(.home(.observableSelected(.lineCall))) { $0.home.observable = .lineCall }
        await store.receive(.home(.delegate(.selectionChanged(.match, .lineCall)))) {
            $0.preferences.lastObservable = .lineCall
        }

        // 볼머신으로 옮기면 라인 판정이 남으면 안 된다. 남겨두면 다시
        // 시합을 골랐을 때 고른 적 없는 배치로 안내된다.
        await store.send(.home(.situationSelected(.ballMachine))) {
            $0.home.situation = .ballMachine
            $0.home.observable = .swing
        }
        await store.receive(.home(.delegate(.selectionChanged(.ballMachine, .swing)))) {
            $0.preferences.lastSituation = .ballMachine
            $0.preferences.lastObservable = .swing
        }
    }

    // MARK: 설정

    @Test("설정에서 감지음을 끄면 저장된다")
    func 설정_소리() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.settingsTapped))
        await store.receive(.home(.delegate(.openSettings))) {
            $0.settings = SettingsFeature.State(handedness: .right, soundEnabled: true)
        }
        await store.send(.settings(.presented(.soundToggled(false)))) {
            $0.settings?.soundEnabled = false
        }
        await store.receive(.settings(.presented(.delegate(.soundToggled(false))))) {
            $0.preferences.soundEnabled = false
        }
        #expect(repo.load().soundEnabled == false, "끈 채로 재실행하면 꺼져 있어야 한다")
    }

    @Test("설정에서 주 사용 손을 바꾸면 저장된다")
    func 설정_손_변경() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.settingsTapped))
        await store.receive(.home(.delegate(.openSettings))) {
            $0.settings = SettingsFeature.State(handedness: .right, soundEnabled: true)
        }
        await store.send(.settings(.presented(.handednessChanged(.left)))) {
            $0.settings?.handedness = .left
        }
        await store.receive(.settings(.presented(.delegate(.handednessChanged(.left))))) {
            $0.preferences.handedness = .left
        }
        #expect(repo.load().handedness == .left)
    }
}

@Suite("촬영 상황")
struct CaptureSituationTests {

    @Test("라인 판정은 시합에서만 고를 수 있다")
    func 시합만() {
        for situation in CaptureSituation.allCases {
            #expect(situation.allowsLineCall == (situation == .match), "\(situation.label)")
        }
    }

    @Test("벽치기만 팔로스루 룰을 무효화한다")
    func 벽치기_룰() {
        #expect(CaptureSituation.wall.disabledRules == ["followThroughAngle"])
        for situation in CaptureSituation.allCases where situation != .wall {
            #expect(situation.disabledRules.isEmpty, "\(situation.label)")
        }
    }

    @Test("관찰 대상마다 배치가 다르다")
    func 배치() {
        #expect(ObservationTarget.swing.placement != ObservationTarget.lineCall.placement)
    }
}

@Suite("촬영 홈 카드")
struct HomeCardTests {

    @Test("시합에서 라인 판정을 골라도 다른 카드의 배치는 그대로다")
    func 카드별_배치() {
        let state = HomeFeature.State(situation: .match, observable: .lineCall)

        for situation in CaptureSituation.allCases {
            let expected: ObservationTarget = situation == .match ? .lineCall : .swing
            #expect(state.cardObservable(for: situation) == expected, "\(situation.label)")
        }
        #expect(state.cardObservable(for: .ballMachine).placement == "코트 옆 6m, 허리 높이")
        #expect(state.cardObservable(for: .match).placement == "판정할 라인의 연장선")
    }

    @Test("고르지 않은 시합 카드는 라인 판정을 내세우지 않는다")
    func 고르지_않은_시합() {
        let state = HomeFeature.State(situation: .ballMachine, observable: .lineCall)

        #expect(state.cardObservable(for: .match) == .swing, "선택되지 않은 카드다")
        #expect(state.effectiveObservable == .swing)
    }

    @Test("다섯 장이 각자 자기 배치를 들고 나온다 — 뷰가 전역값을 읽지 않는다")
    func 카드_목록() {
        let state = HomeFeature.State(situation: .match, observable: .lineCall)
        let cards = state.cards

        #expect(cards.map(\.situation) == CaptureSituation.allCases)
        #expect(cards.filter(\.isSelected).map(\.situation) == [.match])
        #expect(
            cards.filter { $0.placement == "판정할 라인의 연장선" }.map(\.situation) == [.match],
            "라인 판정 배치는 고른 시합 카드에만 찍혀야 한다"
        )
        #expect(
            cards.filter { $0.placement == "코트 옆 6m, 허리 높이" }.map(\.situation)
                == [.ballMachine, .wall, .rally, .lesson]
        )
    }

    @Test("피커는 고른 시합 카드에만 달린다")
    func 피커_노출() {
        let 시합 = HomeFeature.State(situation: .match, observable: .lineCall).cards
        #expect(시합.filter { $0.pickerSelection != nil }.map(\.situation) == [.match])
        #expect(시합.first { $0.situation == .match }?.pickerSelection == .lineCall)

        let 랠리 = HomeFeature.State(situation: .rally, observable: .swing).cards
        #expect(랠리.allSatisfy { $0.pickerSelection == nil }, "시합이 아니면 고를 라인이 없다")
    }

    @Test("고른 카드의 관찰 대상은 시합일 때만 라인 판정이 된다")
    func 선택된_카드() {
        for situation in CaptureSituation.allCases {
            for target in ObservationTarget.allCases {
                let state = HomeFeature.State(situation: situation, observable: target)
                let expected: ObservationTarget = situation.allowsLineCall ? target : .swing

                #expect(state.cardObservable(for: situation) == expected, "\(situation.label)/\(target.label)")
                #expect(state.effectiveObservable == expected, "\(situation.label)/\(target.label)")
            }
        }
    }
}

@Suite("촬영 권한")
struct CapturePermissionPlanTests {

    @Test("카메라가 허용되지 않으면 어떤 조합이든 막는다")
    func 카메라가_먼저다() {
        for camera in [AVAuthorizationStatus.denied, .restricted, .notDetermined] {
            for mic in [AVAuthorizationStatus.authorized, .denied, .restricted, .notDetermined] {
                let plan = CapturePermissionPlan.make(camera: camera, microphone: mic)
                #expect(plan == .blocked, "\(camera.rawValue)/\(mic.rawValue)")
            }
        }
    }

    @Test("마이크가 없어도 촬영은 계속한다 — 무음으로")
    func 마이크는_막지_않는다() {
        for mic in [AVAuthorizationStatus.denied, .restricted, .notDetermined] {
            let plan = CapturePermissionPlan.make(camera: .authorized, microphone: mic)
            #expect(plan == .proceed(audio: false), "\(mic.rawValue)")
            #expect(plan.allowsCapture, "마이크 때문에 스윙 기록 전체를 잃으면 안 된다")
            #expect(plan.recordsAudio == false)
        }
    }

    @Test("둘 다 허용되면 소리까지 녹음한다")
    func 둘_다_허용() {
        let plan = CapturePermissionPlan.make(camera: .authorized, microphone: .authorized)
        #expect(plan == .proceed(audio: true))
        #expect(plan.allowsCapture)
        #expect(plan.recordsAudio)
    }
}

@Suite("촬영 시작 흐름")
@MainActor
struct CaptureFlowTests {

    @Test("홈에서 시작을 누르면 촬영이 열린다 — 고른 것을 들고")
    func 시작하면_열린다() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.startTapped))
        await store.receive(.home(.delegate(.start(.ballMachine, .swing)))) {
            $0.capture = CaptureFeature.State(situation: .ballMachine, observable: .swing, handedness: .right)
        }

        #expect(store.state.capture?.phase == .framing, "촬영은 프레이밍 가이드에서 시작한다")
    }

    @Test("시합에서 고른 라인 판정이 촬영까지 넘어간다")
    func 라인_판정이_넘어간다() async {
        let prefs = UserPreferences(
            handedness: .right,
            lastSituation: .match,
            lastObservable: .lineCall
        )
        let repo = InMemoryRepository(prefs)
        let store = TestStore(initialState: AppFeature.State(preferences: prefs)) {
            AppFeature(repository: repo)
        }

        await store.send(.home(.startTapped))
        await store.receive(.home(.delegate(.start(.match, .lineCall)))) {
            $0.capture = CaptureFeature.State(situation: .match, observable: .lineCall, handedness: .right)
        }

        #expect(store.state.capture?.observable == .lineCall)
        #expect(store.state.capture?.guidance.frame == .line, "배치가 다르면 가이드도 달라야 한다")
    }

    /// 주 사용 손이 없으면 어느 손목을 볼지 정할 수 없어 스윙이 하나도
    /// 잡히지 않는다. 온보딩을 거치지 않으면 도달할 수 없는 경로지만
    /// 상태로도 막는다.
    @Test("주 사용 손이 없으면 촬영이 열리지 않는다")
    func 손_없으면_안_열린다() async {
        let repo = InMemoryRepository(UserPreferences())
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences()
        )) { AppFeature(repository: repo) }

        await store.send(.home(.startTapped))
        await store.receive(.home(.delegate(.start(.ballMachine, .swing))))

        #expect(store.state.capture == nil)
    }

    @Test("촬영을 닫으면 홈으로 돌아온다")
    func 닫으면_홈으로() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        var initial = AppFeature.State(preferences: UserPreferences(handedness: .right))
        initial.capture = CaptureFeature.State(situation: .rally, observable: .swing, handedness: .right)
        let store = TestStore(initialState: initial) { AppFeature(repository: repo) }

        await store.send(.capture(.presented(.closeTapped(savedSessionID: nil))))
        await store.receive(.capture(.presented(.delegate(.finished(sessionID: nil))))) {
            $0.capture = nil
        }
    }

    /// 저장된 세션이 없으면(저장 실패·프레임 0장) 요약을 열지 않는다 —
    /// 보여줄 것이 없는데 화면을 띄우면 사용자는 빈 화면을 본다.
    @Test("저장된 세션이 있으면 요약이 열린다")
    func 요약_열림() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        var initial = AppFeature.State(preferences: UserPreferences(handedness: .right))
        initial.capture = CaptureFeature.State(
            situation: .rally, observable: .swing, handedness: .right
        )
        let store = TestStore(initialState: initial) { AppFeature(repository: repo) }

        let id = UUID()
        await store.send(.capture(.presented(.closeTapped(savedSessionID: id))))
        await store.receive(.capture(.presented(.delegate(.finished(sessionID: id))))) {
            $0.capture = nil
            $0.summary = SessionSummaryFeature.State(sessionID: id)
        }
        #expect(store.state.capture == nil, "촬영을 닫아야 카메라가 내려간다")
    }

    @Test("요약을 닫으면 홈으로 돌아온다")
    func 요약_닫힘() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        var initial = AppFeature.State(preferences: UserPreferences(handedness: .right))
        initial.summary = SessionSummaryFeature.State(sessionID: UUID())
        let store = TestStore(initialState: initial) { AppFeature(repository: repo) }

        await store.send(.summary(.presented(.closeTapped)))
        await store.receive(.summary(.presented(.delegate(.closed)))) { $0.summary = nil }
    }

    /// 진단의 "배치 다시 보기"는 요약을 닫고 촬영을 다시 연다.
    @Test("배치 다시 보기는 촬영을 다시 연다")
    func 배치_다시() async {
        let prefs = UserPreferences(handedness: .left, lastSituation: .wall, lastObservable: .swing)
        let repo = InMemoryRepository(prefs)
        var initial = AppFeature.State(preferences: prefs)
        initial.summary = SessionSummaryFeature.State(sessionID: UUID())
        let store = TestStore(initialState: initial) { AppFeature(repository: repo) }

        await store.send(.summary(.presented(.reframeTapped)))
        await store.receive(.summary(.presented(.delegate(.reframe)))) {
            $0.summary = nil
            $0.capture = CaptureFeature.State(
                situation: .wall, observable: .swing, handedness: .left
            )
        }
        #expect(store.state.capture?.phase == .framing, "배치부터 다시 본다")
    }

    @Test("촬영 시작을 누르면 가이드에서 촬영으로 넘어간다")
    func 단계_전이() async {
        let store = TestStore(
            initialState: CaptureFeature.State(situation: .wall, observable: .swing, handedness: .right)
        ) { CaptureFeature() }

        await store.send(.startTapped) { $0.phase = .capturing }
        // 단계는 되돌아가지 않는다
        await store.send(.startTapped)
    }
}

@Suite("프레이밍 가이드")
struct FramingGuidanceTests {

    @Test("관찰 대상에 따라 담을 것이 다르다")
    func 대상별_가이드() {
        let 스윙 = FramingGuidance.make(for: .swing)
        let 판정 = FramingGuidance.make(for: .lineCall)

        #expect(스윙.frame == .body, "선수가 프레임 높이의 35~45%를 차지해야 한다")
        #expect(판정.frame == .line, "라인이 화면을 가로질러야 한다")
        #expect(스윙.headline != 판정.headline)
    }

    @Test("배치 문구는 Domain이 들고 있는 것을 쓴다 — 두 벌로 갈라지면 안 된다")
    func 배치_문구_재사용() {
        for target in ObservationTarget.allCases {
            let guidance = FramingGuidance.make(for: target)
            #expect(
                guidance.placement.hasPrefix(target.placement),
                "\(target.label): \(guidance.placement)"
            )
        }
    }
}

@Suite("방향 잠금")
@MainActor
struct OrientationLockTests {

    @Test("촬영이 가로를 잠그고, 나가면 풀린다")
    func 잠금과_해제() {
        var applied: [UIInterfaceOrientationMask] = []
        let lock = OrientationLock { applied.append($0) }

        #expect(lock.mask == OrientationLock.unlocked, "기본은 기기 방향을 따른다")
        #expect(
            !lock.mask.contains(.portraitUpsideDown),
            "Info.plist가 뺀 거꾸로를 델리게이트가 되살리면 안 된다"
        )

        lock.lock(to: .landscape)
        #expect(lock.mask == .landscape)

        lock.release()
        #expect(lock.mask == OrientationLock.unlocked, "풀지 않으면 세로 화면 12종이 가로로 남는다")

        // 마스크만 바꾸면 UIKit이 다시 묻지 않는다. 창에 갱신을 요청해야 한다.
        //
        // 해제는 `unlocked`가 아니라 **세로**를 요청한다. 넓히기만 하면
        // 현재 방향(가로)이 허용 집합에 들어 있어 iOS가 그대로 두고,
        // 기기가 세로인데 앱이 가로로 남는다 — #88에서 실측했다.
        #expect(applied == [.landscape, .portrait])
        #expect(lock.mask == OrientationLock.unlocked, "요청은 세로지만 마스크는 넓어야 한다")
    }

    @Test("촬영 화면은 가로를 선언한다")
    func 촬영은_가로다() {
        #expect(CaptureScreen.supportedOrientations == .landscape)
    }
}
