import Data
import Domain
import Foundation
import Presentation

/// 세션 저장소를 세운다.
///
/// 구현체(`SwiftDataSessionRepository`)는 `Data`에 있고 `Presentation`은
/// `Data`를 모른다. 둘을 함께 아는 계층이 `Application`이므로 조립을 여기서
/// 한다 — [아키텍처 2.2](../../../../docs/02-설계/ARCHITECTURE.md).
///
/// **실패해도 던지지 않는다.** 던지면 진입점이 앱을 못 띄우고, 사용자는
/// 촬영도 못 한다. 사유를 값으로 들고 가 화면이 띄우게 한다.
///
/// 근거: docs/07-기획/SPEC-0097-swing-wiring.md 구현 선택지 3
public enum SessionStorageFactory {

    public static func make() -> SessionStorage {
        do {
            return SessionStorage(repository: try SwiftDataSessionRepository())
        } catch {
            return SessionStorage(
                failure: "세션 저장소를 열지 못했습니다 — 촬영은 되지만 기록이 남지 않습니다"
            )
        }
    }
}
