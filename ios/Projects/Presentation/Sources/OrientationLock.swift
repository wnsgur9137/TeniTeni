import UIKit

/// 화면이 자기 방향을 선언한다. 진입점의 `AppDelegate`가 이 `mask`를 UIKit에 답한다.
///
/// **왜 홀더인가.** 제시된 화면(`fullScreenCover`)의 방향은 컨테이너가 답하므로
/// 자식 뷰 컨트롤러에 `supportedInterfaceOrientations`를 선언해도 먹지 않는다.
/// 잠금을 **요청하는 쪽은 촬영 화면**이고, 여기는 그 선언을 들고 있는 자리다.
///
/// 근거: docs/07-기획/SPEC-0061-module-shell.md 구현 선택지 3 · SPEC-0078
@MainActor
public final class OrientationLock {

    public static let shared = OrientationLock(apply: OrientationLock.applyToActiveScene)

    public private(set) var mask: UIInterfaceOrientationMask

    private let apply: @MainActor (UIInterfaceOrientationMask) -> Void

    /// `apply`를 주입받는다 — 테스트가 창을 만들지 않고 전이를 확인할 수 있어야 한다.
    public init(
        mask: UIInterfaceOrientationMask = .all,
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
    public func release() {
        mask = .all
        apply(.all)
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
