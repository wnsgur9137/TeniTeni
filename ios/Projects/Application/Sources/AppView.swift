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
            // 1-A′가 온보딩 → 주 사용 손 흐름으로 채운다.
                TabPlaceholderView(
                    title: "TeniTeni",
                    message: "시작하기 전에 몇 가지를 묻습니다",
                    detail: "온보딩은 1-A′에서 만듭니다"
                )
            }
        }
        .onAppear { store.send(.appeared) }
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
        // 촬영 탭만 진짜 화면이다. 0-A 회귀를 막으려고 그대로 붙였다 —
        // SPEC-0061 구현 선택지 2.
        case .capture: CaptureView()
        case .library: LibraryPlaceholderView()
        case .progress: ProgressPlaceholderView()
        }
    }
}
