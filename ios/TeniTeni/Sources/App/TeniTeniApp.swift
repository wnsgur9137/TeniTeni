import Application
import ComposableArchitecture
import Presentation
import SwiftUI
import UIKit

/// 진입점은 **스토어를 만들고 루트 뷰를 띄우는 것만** 한다.
/// 화면을 직접 띄우지 않는 것이 1-A의 목적이다 — 예전에는 여기서
/// 촬영 화면을 바로 띄웠다.
@main
struct TeniTeniApp: App {
    /// 방향은 화면이 선언한다. UIKit에 답하는 창구만 여기 둔다 —
    /// 제시된 화면의 방향은 컨테이너가 답하므로 창구가 필요하다.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// 세션 저장소는 앱 수명 내내 하나다. 실패하면 사유를 들고 간다 —
    /// 던지면 앱이 안 뜨고 촬영조차 못 한다.
    private static let storage = SessionStorageFactory.make()

    /// 촬영은 `storage`로 쓰고, 요약은 같은 저장소에서 **다시 읽는다.**
    /// 저장소를 못 세운 경우에는 읽기가 사유를 들고 실패한다.
    @MainActor
    private static let store = Store(initialState: AppFeature.State()) {
        AppFeature(
            sessionRepository: storage.repository ?? UnavailableSessionRepository()
        )
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store, storage: Self.storage)
                .preferredColorScheme(.dark)
        }
    }
}

/// 진입점이 화면을 띄우지 않는다는 원칙은 유지한다. 이 델리게이트는
/// **방향 질문에만** 답한다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientation.mask
    }
}
