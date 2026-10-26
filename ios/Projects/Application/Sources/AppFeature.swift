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
        /// `nil`이면 요약이 닫혀 있다. 촬영이 **저장된 세션을 들고** 끝날
        /// 때만 생긴다 — 보여줄 것이 없는데 열지 않는다.
        @Presents public var summary: SessionSummaryFeature.State?

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
        case summary(PresentationAction<SessionSummaryFeature.Action>)
    }

    private let repository: any UserPreferencesRepository
    /// 요약이 세션을 **다시 읽는다.** 넘겨받은 값을 그리면 저장 실패를
    /// 영원히 모른다(SPEC-0110 선택지 1).
    private let sessionRepository: any SessionRepository

    /// 기본 저장소는 실행 인자를 보고 정해진다 — UI 테스트로 실행하면
    /// **빈 상태**에서 시작한다. 진입점은 `Application`만 알아야 하므로
    /// (`Project.swift`) 그 판단을 여기서 한다. 근거: `LaunchDefaults`, #88
    public init(
        repository: any UserPreferencesRepository = UserDefaultsUserPreferencesRepository(
            defaults: LaunchDefaults.resolve()
        ),
        sessionRepository: any SessionRepository = UnavailableSessionRepository()
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
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
                // 주 사용 손이 없으면 스윙을 잡을 수 없다. 온보딩을 거치지
                // 않으면 도달할 수 없는 경로지만 상태로도 막는다.
                guard let hand = state.preferences.handedness else { return .none }
                // 고른 것을 그대로 넘긴다. 촬영 중에는 바꿀 수 없다 —
                // 바꾸려면 삼각대를 옮겨야 하는 선택이다.
                state.capture = CaptureFeature.State(
                    situation: situation,
                    observable: observable,
                    handedness: hand
                )
                return .none

            case .capture(.presented(.delegate(.finished(let sessionID)))):
                // 촬영을 **먼저 닫는다.** 그래야 카메라 세션이 내려가고,
                // 요약을 보는 동안 카메라가 떠 있지 않는다 — D-03의
                // "Application 경유"가 이 순서를 가능하게 한다.
                state.capture = nil
                // 저장된 세션이 없으면(저장 실패·프레임 0장) 홈으로 간다.
                guard let sessionID else { return .none }
                state.summary = SessionSummaryFeature.State(sessionID: sessionID)
                return .none

            case .summary(.presented(.delegate(.closed))):
                state.summary = nil
                return .none

            case .summary(.presented(.delegate(.reframe))):
                // 진단의 "배치 다시 보기" — 요약을 닫고 촬영을 다시 연다.
                // 고른 상황은 그대로 쓴다.
                state.summary = nil
                guard let hand = state.preferences.handedness else { return .none }
                state.capture = CaptureFeature.State(
                    situation: state.preferences.lastSituation,
                    observable: state.preferences.lastObservable,
                    handedness: hand
                )
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

            case .onboarding, .home, .settings, .capture, .summary:
                return .none
            }
        }
        .ifLet(\.$settings, action: \.settings) { SettingsFeature() }
        .ifLet(\.$capture, action: \.capture) { CaptureFeature() }
        .ifLet(\.$summary, action: \.summary) { SessionSummaryFeature(repository: sessionRepository) }
    }
}
