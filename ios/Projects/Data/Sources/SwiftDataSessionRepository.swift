import Domain
import Foundation
import SwiftData

/// D-08이 확정한 SwiftData 구현. **메타데이터만** 담는다 — 영상 파일은
/// 파일 시스템에 있고 여기에는 이름만 남는다.
///
/// ⚠️ **액터인 이유.** 처음에는 `final class … @unchecked Sendable`이었다.
/// 프로토콜이 `Sendable`을 요구하는데 내부에 `ModelContext`를 들고 있으니
/// 컴파일러가 막았고, `@unchecked`로 막은 것을 치웠던 것이다. 그러나
/// `@unchecked`는 "다른 수단으로 안전을 보장했다"는 선언인데 락도 전용
/// 큐도 액터 격리도 없었다 — 보장하는 수단이 없었다.
///
/// 1-B에서 촬영이 붙으면 바로 만들어지는 조합이다. 캡처 델리게이트 큐에서
/// `save`를 호출하는 동안 MainActor가 보관함을 열어 `loadAll`을 호출하면
/// 같은 `ModelContext`에 진짜 동시 접근이 일어난다. 크래시하거나, 더 나쁘게는
/// 부분적으로 반영된 그래프가 커밋되어 스토어가 손상된다. 단위 테스트는
/// 전부 단일 스레드라 이것을 반증하지 못한다.
///
/// `@ModelActor`는 컨텍스트를 액터의 직렬 실행기에 묶는다. `@unchecked`가
/// 사라지고 컴파일러가 실제로 검사한다 — D-04가 요구하는 형태다.
@ModelActor
public actor SwiftDataSessionRepository: SessionRepository {

    private static let schema = Schema([SessionModel.self, ClipModel.self, SwingModel.self])

    /// - Parameter inMemory: 테스트용. 디스크를 건드리지 않는다.
    public init(inMemory: Bool = false) throws {
        self.init(modelContainer: try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)]
        ))
    }

    /// 저장 위치를 직접 준다. **왕복 테스트가 이것을 쓴다** — 같은 URL로
    /// 컨테이너를 새로 열어야 메모리 캐시가 아니라 디스크에 쓰인 것을 읽는다.
    /// 컨테이너를 공유한 채 `ModelContext`만 새로 만들면 저장이 안 돼도
    /// 테스트가 통과한다.
    public init(storeURL: URL) throws {
        self.init(modelContainer: try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, url: storeURL)]
        ))
    }

    public func save(_ session: Session) throws {
        // 같은 id가 있으면 갈아끼운다. upsert가 없으므로 지우고 넣는다.
        if let existing = try fetch(id: session.id) {
            modelContext.delete(existing)
        }
        modelContext.insert(SessionModel(session))
        try commit()
    }

    public func load(id: UUID) throws -> Session? {
        try fetch(id: id)?.domain
    }

    public func loadAll() throws -> [Session] {
        let descriptor = FetchDescriptor<SessionModel>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.domain)
    }

    public func delete(id: UUID) throws {
        guard let model = try fetch(id: id) else { return }
        modelContext.delete(model)
        try commit()
    }

    /// 실패하면 **되돌린다.**
    ///
    /// `save()`가 던져도 컨텍스트의 미반영 변경은 그대로 남는다. 디스크가 꽉 차
    /// `save(A)`가 실패하면 사용자는 "저장 실패"를 듣지만 A의 insert는 살아 있고,
    /// 나중에 성공하는 `save(B)`가 **A와 B를 함께 커밋한다.** 저장에 실패했다고
    /// 들은 세션이 보관함에 나타난다. 삭제도 대칭으로 같다.
    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func fetch(id: UUID) throws -> SessionModel? {
        var descriptor = FetchDescriptor<SessionModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
