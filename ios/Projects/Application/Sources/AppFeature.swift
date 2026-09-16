import ComposableArchitecture
import Data
import Domain
import Foundation

/// 앱의 루트. **진입점이 화면을 직접 띄우지 않게** 하는 것이 1-A의 목적이다.
///
/// 지금은 분기가 하나뿐이다 — 온보딩을 마쳤는가. 1-A′가 그 양쪽을
/// 실제 화면으로 채운다 (온보딩 · 주 사용 손 · 홈 · 설정).
///
/// 근거: docs/07-기획/SPEC-0061-module-shell.md 구현 선택지 1
@Reducer
public struct AppFeature {

    @ObservableState
    public struct State: Equatable {
        /// 저장된 설정. **주 사용 손이 정해져야** 온보딩을 마친 것이다 —
        /// 둘을 따로 두면 "온보딩은 끝났는데 손을 모르는" 상태가 생긴다.
        public var preferences: UserPreferences
        public var tab: Tab

        public var hasCompletedOnboarding: Bool { preferences.hasCompletedOnboarding }

        public init(preferences: UserPreferences = UserPreferences(), tab: Tab = .capture) {
            self.preferences = preferences
            self.tab = tab
        }
    }

    /// 탭바 3개. 탭 하나가 할 일 하나다 — 찍는다 / 찾는다 / 본다.
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
        case handednessChosen(Handedness)
    }

    private let repository: any UserPreferencesRepository

    public init(repository: any UserPreferencesRepository = UserDefaultsUserPreferencesRepository()) {
        self.repository = repository
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                state.preferences = repository.load()
                return .none

            case .tabSelected(let tab):
                state.tab = tab
                return .none

            // 1-A′의 주 사용 손 화면이 이 액션을 보낸다.
            case .handednessChosen(let hand):
                state.preferences.handedness = hand
                repository.save(state.preferences)
                return .none
            }
        }
    }
}
