import Application
import ComposableArchitecture
import SwiftUI

/// 진입점은 **스토어를 만들고 루트 뷰를 띄우는 것만** 한다.
/// 화면을 직접 띄우지 않는 것이 1-A의 목적이다 — 예전에는 여기서
/// `CaptureView()`를 바로 띄웠다.
@main
struct TeniTeniApp: App {
    @MainActor
    private static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
                .preferredColorScheme(.dark)
        }
    }
}
