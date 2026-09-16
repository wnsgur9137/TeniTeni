import ComposableArchitecture
import DesignSystem
import Presentation
import SwiftUI

/// 루트 뷰. `TeniTeniApp`이 이것만 띄운다.
public struct AppView: View {
    @Bindable private var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
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
        // 촬영 탭 루트는 홈(상황 선택)이다. CaptureView는 1-B가
        // "시작"에 연결한다 — 지금은 선택만 저장된다.
        case .capture: HomeView(store: store.scope(state: \.home, action: \.home))
        case .library: LibraryPlaceholderView()
        case .progress: ProgressPlaceholderView()
        }
    }
}
