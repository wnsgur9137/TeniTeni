import ComposableArchitecture
import Domain
import Foundation
import Presentation
import Testing
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

    @Test("설정에서 주 사용 손을 바꾸면 저장된다")
    func 설정_손_변경() async {
        let repo = InMemoryRepository(UserPreferences(handedness: .right))
        let store = TestStore(initialState: AppFeature.State(
            preferences: UserPreferences(handedness: .right)
        )) { AppFeature(repository: repo) }

        await store.send(.home(.settingsTapped))
        await store.receive(.home(.delegate(.openSettings))) {
            $0.settings = SettingsFeature.State(handedness: .right)
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
