import Foundation

/// 실행 인자를 보고 **어느 `UserDefaults`를 쓸지** 정한다.
///
/// ## 왜 필요한가
///
/// `XCUIApplication.launch()`는 앱 상태를 지우지 않는다. 앞선 실행이 남긴
/// 온보딩 완료와 지난 선택이 그대로 읽히므로, UI 테스트 결과가 **그
/// 시뮬레이터에 무엇이 남아 있었는지**에 달린다.
///
/// 실제로 그 때문에 게이트가 깨졌다 — 선택된 상황 카드는 접근성 트리에서
/// 버튼이 아니라서(#76) `시합`이 미리 선택돼 있으면 테스트가 그 카드를
/// 찾지 못한다. CI는 매번 새 시뮬레이터라 통과하고 **로컬에서만 깨진다.**
/// 근거: 이슈 #88
///
/// ## 왜 앱에 테스트용 경로를 두는가
///
/// 대안은 게이트가 UI 테스트 전에 `simctl uninstall`을 돌리는 것이었다.
/// 그러면 게이트는 고쳐지지만 **테스트 자체는 여전히 상태에 의존한다** —
/// Xcode에서 직접 돌리면 똑같이 깨진다. 밀폐성은 테스트가 가져야 한다.
public enum LaunchDefaults {

    /// UI 테스트가 넘기는 실행 인자.
    public static let uiTestingArgument = "-ui-testing"

    /// 매 실행 시작에 비워지는 스위트 이름.
    static let uiTestingSuiteName = "com.wnsgur9137.TeniTeni.uiTesting"

    /// - Returns: 평소에는 `.standard`, UI 테스트에서는 **비워진 스위트**.
    public static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> UserDefaults {
        guard arguments.contains(uiTestingArgument) else { return .standard }
        // 이름을 고정하고 열기 전에 지운다. 실행마다 새 이름을 만들면
        // 시뮬레이터에 plist가 쌓이고, 지워지는 시점이 없다.
        UserDefaults().removePersistentDomain(forName: uiTestingSuiteName)
        return UserDefaults(suiteName: uiTestingSuiteName) ?? .standard
    }
}
