import ComposableArchitecture
import Data
import Domain
import Foundation
import Presentation

/// 앱의 루트. 진입점이 화면을 직접 띄우지 않게 한다.
///
/// 자식 Feature끼리는 서로를 모른다 — D-03이 "`Presentation` 내 Feature 간
/// 직접 의존 금지, `Application` 코디네이터 경유"를 정했다. 조합은 여기서만
/// 하고, 자식은 `delegate`로 올려보낸다.
@Reducer
public struct AppFeature {

    @ObservableState
    public struct State: Equatable {
        public var preferences: UserPreferences
        public var tab: Tab
        public var onboarding: OnboardingFeature.State
        public var home: HomeFeature.State
        /// `nil`이면 설정이 닫혀 있다. `@Presents`라야 `sheet(item:)`이
        /// 받는 `PresentationAction` 래핑이 생긴다.
        @Presents public var settings: SettingsFeature.State?
        /// `nil`이면 촬영이 닫혀 있다. 홈에서 '시작'을 누를 때만 생긴다.
        @Presents public var capture: CaptureFeature.State?

        public var hasCompletedOnboarding: Bool { preferences.hasCompletedOnboarding }

        public init(
            preferences: UserPreferences = UserPreferences(),
            tab: Tab = .capture
        ) {
            self.preferences = preferences
            self.tab = tab
            self.onboarding = OnboardingFeature.State()
            self.home = HomeFeature.State(
                situation: preferences.lastSituation,
                observable: preferences.lastObservable
            )
            self.settings = nil
        }
    }

    /// 탭 하나가 할 일 하나다 — 찍는다 / 찾는다 / 본다.
    /// 근거: docs/06-디자인/IA-FLOW.md 10.2
    public enum Tab: String, CaseIterable, Equatable, Sendable {
        case capture
        case library
        case progress

        public var title: String {
            switch self {
            case .capture: "촬영"
            case .library: "보관함"
            case .progress: "진척도"
            }
        }

        public var systemImage: String {
            switch self {
            case .capture: "camera"
            case .library: "square.stack"
            case .progress: "chart.line.uptrend.xyaxis"
            }
        }
    }

    public enum Action: Equatable {
        case appeared
        case tabSelected(Tab)
        case onboarding(OnboardingFeature.Action)
        case home(HomeFeature.Action)
        case settings(PresentationAction<SettingsFeature.Action>)
        case capture(PresentationAction<CaptureFeature.Action>)
    }

    private let repository: any UserPreferencesRepository

    public init(repository: any UserPreferencesRepository = UserDefaultsUserPreferencesRepository()) {
        self.repository = repository
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.onboarding, action: \.onboarding) { OnboardingFeature() }
        Scope(state: \.home, action: \.home) { HomeFeature() }

        Reduce { state, action in
            switch action {
            case .appeared:
                state.preferences = repository.load()
                state.home = HomeFeature.State(
                    situation: state.preferences.lastSituation,
                    observable: state.preferences.lastObservable
                )
                return .none

            case .tabSelected(let tab):
                state.tab = tab
                return .none

            case .onboarding(.delegate(.completed(let hand))):
                state.preferences.handedness = hand
                repository.save(state.preferences)
                return .none

            case .home(.delegate(.selectionChanged(let situation, let observable))):
                state.preferences.lastSituation = situation
                state.preferences.lastObservable = observable
                repository.save(state.preferences)
                return .none

            case .home(.delegate(.openSettings)):
                // 주 사용 손이 없으면 설정을 열 수 없다 — 온보딩 전에는
                // 도달할 수 없는 경로지만 상태로도 막는다.
                guard let hand = state.preferences.handedness else { return .none }
                state.settings = SettingsFeature.State(
                    handedness: hand,
                    soundEnabled: state.preferences.soundEnabled
                )
                return .none

            case .home(.delegate(.start(let situation, let observable))):
                // 고른 것을 그대로 넘긴다. 촬영 중에는 바꿀 수 없다 —
                // 바꾸려면 삼각대를 옮겨야 하는 선택이다.
                state.capture = CaptureFeature.State(
                    situation: situation,
                    observable: observable
                )
                return .none

            case .capture(.presented(.delegate(.finished))):
                state.capture = nil
                return .none

            case .settings(.presented(.delegate(.handednessChanged(let hand)))):
                state.preferences.handedness = hand
                repository.save(state.preferences)
                return .none

            case .settings(.presented(.delegate(.soundToggled(let on)))):
                state.preferences.soundEnabled = on
                repository.save(state.preferences)
                return .none

            case .settings(.presented(.delegate(.close))):
                state.settings = nil
                return .none

            case .onboarding, .home, .settings, .capture:
                return .none
            }
        }
        .ifLet(\.$settings, action: \.settings) { SettingsFeature() }
        .ifLet(\.$capture, action: \.capture) { CaptureFeature() }
    }
}
