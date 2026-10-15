import Foundation

/// 구현은 `Data`에 있다. `Domain`은 **무엇이 필요한지**만 말한다 —
/// 9.6의 의존성 방향 규칙.
///
/// D-08이 "교체 비용은 Data 계층에 한정된다"고 약속했으므로, 저장 방식이
/// 바뀌어도 이 프로토콜과 엔티티는 그대로여야 한다.
///
/// ⚠️ 메서드가 `async`인 이유는 저장이 느려서가 아니라 **구현이 액터여야
/// 하기 때문**이다. SwiftData의 `ModelContext`는 스레드 안전하지 않은데
/// 이 프로토콜은 `Sendable`을 요구한다. 동기 시그니처로 두면 구현은
/// `@unchecked Sendable`로 컴파일러를 속이는 수밖에 없고, 촬영 큐와
/// MainActor가 같은 컨텍스트를 동시에 건드리게 된다.
public protocol SessionRepository: Sendable {
    func save(_ session: Session) async throws
    func load(id: UUID) async throws -> Session?
    /// 최근 것부터. 보관함이 그 순서로 보여준다.
    func loadAll() async throws -> [Session]
    /// 클립·스윙도 함께 지운다. 세션 없는 클립은 의미가 없다.
    func delete(id: UUID) async throws
}
