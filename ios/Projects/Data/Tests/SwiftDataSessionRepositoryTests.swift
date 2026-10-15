import Domain
import Foundation
import SwiftData
import Testing
@testable import Data

/// 테스트마다 새 저장 파일을 쓴다. 남으면 다음 테스트가 앞선 테스트의
/// 데이터를 본다.
private struct TempStore: ~Copyable {
    let url: URL

    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("teni-\(UUID().uuidString).store")
    }

    deinit {
        // SwiftData는 -wal·-shm도 만든다. 셋 다 지운다.
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix)
            )
        }
    }
}

/// 저장된 파일을 **저장소를 거치지 않고** 직접 센다. cascade가 정말
/// 지웠는지 보려면 `SessionRepository`가 보여주는 것 말고 실제 행을 봐야 한다.
private func rowCounts(at url: URL) throws -> (sessions: Int, clips: Int, swings: Int) {
    let schema = Schema([SessionModel.self, ClipModel.self, SwingModel.self])
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, url: url)]
    )
    let context = ModelContext(container)
    return (
        try context.fetchCount(FetchDescriptor<SessionModel>()),
        try context.fetchCount(FetchDescriptor<ClipModel>()),
        try context.fetchCount(FetchDescriptor<SwingModel>())
    )
}

private func makeSession(
    startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    situation: CaptureSituation = .rally,
    swingKinds: [SwingKind?] = [.forehand, nil]
) -> Session {
    let swings = swingKinds.enumerated().map { index, kind in
        Swing(
            startSeconds: Double(index) * 2,
            endSeconds: Double(index) * 2 + 1.5,
            impactSeconds: Double(index) * 2 + 0.8,
            kind: kind
        )
    }
    return Session(
        startedAt: startedAt,
        endedAt: startedAt.addingTimeInterval(600),
        situation: situation,
        observable: situation.allowsLineCall ? .lineCall : .swing,
        fps: 120,
        clips: [
            Clip(
                fileName: "clip-0.mov",
                recordedAt: startedAt.addingTimeInterval(5),
                fps: 120,
                swings: swings
            )
        ]
    )
}

@Suite("SwiftDataSessionRepository")
struct SwiftDataSessionRepositoryTests {

    // MARK: - 왕복

    /// ⚠️ **새 컨테이너에서 읽는다.** 같은 컨테이너에서 읽으면 메모리
    /// 캐시를 보게 되어 디스크에 실제로 쓰였는지 확인되지 않는다.
    /// 근거: SPEC-0070 검증 방법
    @Test("저장한 세션을 새 컨테이너에서 읽으면 같다")
    func 왕복() throws {
        let store = TempStore()
        let session = makeSession()

        let writer = try SwiftDataSessionRepository(storeURL: store.url)
        try writer.save(session)

        let reader = try SwiftDataSessionRepository(storeURL: store.url)
        let loaded = try #require(try reader.load(id: session.id))

        #expect(loaded == session)
    }

    @Test("클립과 스윙이 함께 왕복한다")
    func 중첩_왕복() throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [.serve, .backhand, nil])

        try SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.clips.count == 1)
        #expect(loaded.swingCount == 3)
        #expect(loaded.clips[0].swings.map(\.kind) == [.serve, .backhand, nil])
    }

    @Test("아직 분류되지 않은 스윙은 kind가 nil로 남는다")
    func 미분류_스윙() throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [nil])

        try SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.clips[0].swings[0].kind == nil)
    }

    @Test("없는 id를 읽으면 nil이다")
    func 없는_세션() throws {
        let store = TempStore()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        #expect(try repository.load(id: UUID()) == nil)
    }

    @Test("같은 id로 다시 저장하면 갈아끼운다")
    func 덮어쓰기() throws {
        let store = TempStore()
        var session = makeSession()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try repository.save(session)

        session.clips[0].fileName = "clip-renamed.mov"
        try repository.save(session)

        #expect(try repository.loadAll().count == 1)
        let counts = try rowCounts(at: store.url)
        #expect(counts.clips == 1, "덮어쓰기가 옛 클립을 남기면 고아 행이 쌓인다")
        #expect(
            try SwiftDataSessionRepository(storeURL: store.url)
                .load(id: session.id)?.clips[0].fileName == "clip-renamed.mov"
        )
    }

    @Test("최근 세션이 먼저 나온다")
    func 정렬() throws {
        let store = TempStore()
        let old = makeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        let new = makeSession(startedAt: Date(timeIntervalSince1970: 2_000))
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try repository.save(old)
        try repository.save(new)

        #expect(try repository.loadAll().map(\.id) == [new.id, old.id])
    }

    // MARK: - cascade

    /// 이 테스트는 **행을 직접 센다.** `loadAll()`이 0을 준다고 해서
    /// 클립·스윙 행이 지워졌다는 뜻은 아니다 — 세션만 지우고 고아가
    /// 남아도 저장소 API로는 똑같이 보인다.
    @Test("세션을 지우면 클립과 스윙도 지워진다")
    func cascade_삭제() throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [.forehand, .backhand])
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try repository.save(session)

        let before = try rowCounts(at: store.url)
        #expect(before == (sessions: 1, clips: 1, swings: 2))

        try repository.delete(id: session.id)

        let after = try rowCounts(at: store.url)
        #expect(after == (sessions: 0, clips: 0, swings: 0))
    }

    @Test("없는 id를 지우면 아무 일도 없다")
    func 없는_세션_삭제() throws {
        let store = TempStore()
        let session = makeSession()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try repository.save(session)

        try repository.delete(id: UUID())

        #expect(try repository.loadAll().count == 1)
    }

    // MARK: - 상황 보존

    @Test("상황과 관찰 대상이 그대로 돌아온다", arguments: CaptureSituation.allCases)
    func 상황_왕복(_ situation: CaptureSituation) throws {
        let store = TempStore()
        let session = makeSession(situation: situation)

        try SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.situation == situation)
        #expect(loaded.observable == session.observable)
    }
}
