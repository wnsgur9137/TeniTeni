import Domain
import Foundation

/// 세션 저장소와 그 생성 결과.
///
/// ## 왜 실패를 값으로 들고 다니는가
///
/// `SwiftDataSessionRepository`는 `ModelContainer`를 세우므로 **생성이
/// 실패할 수 있다.** 실패했을 때 촬영 자체를 막으면 사용자는 아무것도 할
/// 수 없고, 그냥 넘기면 **찍었는데 아무것도 남지 않는다.**
///
/// 그래서 촬영은 되게 하되 **사유를 들고 다닌다.** 화면이 그것을 띄운다 —
/// 끝난 뒤에 알면 다시 찍을 수 없다.
///
/// ## 왜 Presentation에 있는가
///
/// 구현체는 `Data`에 있고 `Presentation`은 `Data`를 모른다(`Project.swift`).
/// 그래서 **타입은 여기 두고 값은 `Application`이 만들어 내려보낸다** —
/// 프레임 경로는 TCA 바깥이라([D-03](../../../../../docs/05-결정/stack/D-03-architecture-pattern.md))
/// 의존성 주입도 명시적으로 한다.
///
/// 근거: docs/07-기획/SPEC-0097-swing-wiring.md 구현 선택지 3
public struct SessionStorage: Sendable {

    public let repository: (any SessionRepository)?
    /// 저장소를 세우지 못한 사유. `repository`가 `nil`이면 반드시 채워진다.
    public let failure: String?

    public init(repository: any SessionRepository) {
        self.repository = repository
        self.failure = nil
    }

    public init(failure: String) {
        self.repository = nil
        self.failure = failure
    }

    /// 저장할 수 없는 상태인가.
    public var isUnavailable: Bool { repository == nil }
}
