import Foundation

/// 구현은 `Data`에 있다. `Domain`은 **무엇이 필요한지**만 말한다 —
/// 9.6의 의존성 방향 규칙.
///
/// D-08이 "교체 비용은 Data 계층에 한정된다"고 약속했으므로, 저장 방식이
/// 바뀌어도 이 프로토콜과 엔티티는 그대로여야 한다.
public protocol SessionRepository: Sendable {
    func save(_ session: Session) throws
    func load(id: UUID) throws -> Session?
    /// 최근 것부터. 보관함이 그 순서로 보여준다.
    func loadAll() throws -> [Session]
    /// 클립·스윙도 함께 지운다. 세션 없는 클립은 의미가 없다.
    func delete(id: UUID) throws
}
