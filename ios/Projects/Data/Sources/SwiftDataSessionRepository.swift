import Domain
import Foundation
import SwiftData

/// D-08이 확정한 SwiftData 구현. **메타데이터만** 담는다 — 영상 파일은
/// 파일 시스템에 있고 여기에는 이름만 남는다.
public final class SwiftDataSessionRepository: SessionRepository, @unchecked Sendable {
    private let container: ModelContainer
    private let context: ModelContext

    /// - Parameter inMemory: 테스트용. 디스크를 건드리지 않는다.
    public convenience init(inMemory: Bool = false) throws {
        try self.init(configuration: ModelConfiguration(
            schema: Self.schema, isStoredInMemoryOnly: inMemory
        ))
    }

    /// 저장 위치를 직접 준다. **왕복 테스트가 이것을 쓴다** — 같은 URL로
    /// 컨테이너를 새로 열어야 메모리 캐시가 아니라 디스크에 쓰인 것을 읽는다.
    /// 컨테이너를 공유한 채 `ModelContext`만 새로 만들면 저장이 안 돼도
    /// 테스트가 통과한다.
    public convenience init(storeURL: URL) throws {
        try self.init(configuration: ModelConfiguration(schema: Self.schema, url: storeURL))
    }

    private init(configuration: ModelConfiguration) throws {
        container = try ModelContainer(for: Self.schema, configurations: [configuration])
        context = ModelContext(container)
    }

    private static let schema = Schema([SessionModel.self, ClipModel.self, SwingModel.self])

    public func save(_ session: Session) throws {
        // 같은 id가 있으면 갈아끼운다. upsert가 없으므로 지우고 넣는다.
        if let existing = try fetch(id: session.id) {
            context.delete(existing)
        }
        context.insert(SessionModel(session))
        try context.save()
    }

    public func load(id: UUID) throws -> Session? {
        try fetch(id: id)?.domain
    }

    public func loadAll() throws -> [Session] {
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    public func delete(id: UUID) throws {
        guard let model = try fetch(id: id) else { return }
        context.delete(model)
        try context.save()
    }

    private func fetch(id: UUID) throws -> SessionModel? {
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
