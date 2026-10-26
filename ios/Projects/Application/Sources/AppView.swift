import ComposableArchitecture
import DesignSystem
import Presentation
import SwiftUI

/// 루트 뷰. `TeniTeniApp`이 이것만 띄운다.
public struct AppView: View {
    @Bindable private var store: StoreOf<AppFeature>
    /// 세션 저장소. 생성 실패도 값으로 들고 온다 — 촬영은 되고 저장만
    /// 안 되는 상태를 화면이 알려야 한다.
    private let storage: SessionStorage

    public init(store: StoreOf<AppFeature>, storage: SessionStorage) {
        self.store = store
        self.storage = storage
    }

    public var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView(
                    store: store.scope(state: \.onboarding, action: \.onboarding)
                )
            }
        }
        .onAppear { store.send(.appeared) }
        .sheet(item: $store.scope(state: \.settings, action: \.settings)) { settingsStore in
            SettingsView(store: settingsStore)
        }
        // 촬영은 탭바를 덮는다. 6m 밖에서는 탭을 잘못 눌러도 알아채지 못한다.
        .fullScreenCover(item: $store.scope(state: \.capture, action: \.capture)) { captureStore in
            CaptureScreen(store: captureStore, storage: storage)
        }
    }

    private var tabs: some View {
        TabView(selection: $store.tab.sending(\.tabSelected)) {
            ForEach(AppFeature.Tab.allCases, id: \.self) { tab in
                content(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(Token.Accent.primary)
    }

    @ViewBuilder
    private func content(for tab: AppFeature.Tab) -> some View {
        switch tab {
        // 촬영 탭 루트는 홈(상황 선택)이다. '시작'을 누르면 촬영이
        // 탭 위로 덮인다 — `fullScreenCover`.
        case .capture: HomeView(store: store.scope(state: \.home, action: \.home))
        case .library: LibraryPlaceholderView()
        case .progress: ProgressPlaceholderView()
        }
    }
}
