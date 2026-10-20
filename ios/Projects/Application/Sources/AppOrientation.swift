import Presentation
import UIKit

/// 진입점이 방향을 물어보는 창구.
///
/// 앱 타깃은 `Application`만 안다(docs/04-계획/WORK-PLAN.md 9.6). `Presentation`의
/// 타입을 진입점까지 끌어올리지 않기 위해 UIKit 값만 건넨다.
@MainActor
public enum AppOrientation {
    public static var mask: UIInterfaceOrientationMask { OrientationLock.shared.mask }
}
