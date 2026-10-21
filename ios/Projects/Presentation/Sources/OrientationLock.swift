import UIKit

/// 화면이 자기 방향을 선언한다. 진입점의 `AppDelegate`가 이 `mask`를 UIKit에 답한다.
///
/// **왜 홀더인가.** 시스템은 루트 또는 **창을 채우는 최상위 모달** 뷰 컨트롤러에
/// 방향을 묻는데, SwiftUI의 `fullScreenCover`가 세우는 호스팅 컨트롤러는 상속해
/// `supportedInterfaceOrientations`를 선언할 수 없다. 잠금을 **요청하는 쪽은
/// 촬영 화면**이고, 여기는 그 선언을 들고 있는 자리다.
///
/// 근거: docs/07-기획/SPEC-0061-module-shell.md 구현 선택지 3 · SPEC-0078
@MainActor
public final class OrientationLock {

    public static let shared = OrientationLock(apply: OrientationLock.applyToActiveScene)

    /// 잠금이 없을 때의 마스크. `.all`을 쓰면 `Info.plist`가 의도적으로 뺀
    /// 거꾸로가 되살아난다 — 앱 델리게이트의 답이 plist를 **대체**하기 때문이다.
    public static let unlocked: UIInterfaceOrientationMask = [
        .portrait, .landscapeLeft, .landscapeRight,
    ]

    public private(set) var mask: UIInterfaceOrientationMask

    private let apply: @MainActor (UIInterfaceOrientationMask) -> Void

    /// `apply`를 주입받는다 — 테스트가 창을 만들지 않고 전이를 확인할 수 있어야 한다.
    public init(
        mask: UIInterfaceOrientationMask = OrientationLock.unlocked,
        apply: @escaping @MainActor (UIInterfaceOrientationMask) -> Void
    ) {
        self.mask = mask
        self.apply = apply
    }

    public func lock(to mask: UIInterfaceOrientationMask) {
        self.mask = mask
        apply(mask)
    }

    /// 촬영에서 나가면 다시 기기 방향을 따른다.
    /// 풀지 않으면 세로 화면 12종이 가로로 남는다.
    ///
    /// ## 왜 넓히는 것만으로는 부족한가
    ///
    /// 마스크를 `unlocked`로 넓히고 갱신을 요청하면, iOS는 **현재 방향을
    /// 그대로 둔다** — 가로가 허용 집합에 들어 있으므로 바꿀 이유가 없다.
    /// 기기가 세로인데 앱만 가로로 남는다. 기기는 애초에 돌아간 적이
    /// 없으므로(앱만 돌았다) 새 회전 이벤트도 오지 않는다.
    ///
    /// 실측: 촬영을 나온 뒤 창 874×402(가로), 기기 방향 `.portrait`,
    /// 홈 화면 표시. 10초를 기다려도 돌아오지 않는다 — 이슈 #88
    ///
    /// 그래서 **세로를 명시해 요청한다.** 마스크는 `unlocked`로 두므로
    /// 그 뒤에 기기를 돌리면 따라간다 — 되돌릴 방향을 한 번 지정하는 것과
    /// 이후 자유를 막는 것은 다르다.
    public func release() {
        mask = Self.unlocked
        apply(.portrait)
    }

    /// 마스크만 바꾸면 UIKit은 다시 묻지 않는다. 현재 창에 갱신을 요청해야 즉시 돈다.
    private static func applyToActiveScene(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
