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

private let testSchema = Schema([SessionModel.self, ClipModel.self, SwingModel.self])

/// 저장된 파일을 **저장소를 거치지 않고** 직접 센다. cascade가 정말
/// 지웠는지 보려면 `SessionRepository`가 보여주는 것 말고 실제 행을 봐야 한다.
private func rowCounts(at url: URL) throws -> (sessions: Int, clips: Int, swings: Int) {
    let context = ModelContext(try rawContainer(at: url))
    return (
        try context.fetchCount(FetchDescriptor<SessionModel>()),
        try context.fetchCount(FetchDescriptor<ClipModel>()),
        try context.fetchCount(FetchDescriptor<SwingModel>())
    )
}

/// 저장소를 거치지 않고 행을 직접 쓰기 위한 컨테이너. "앞선 버전이 써 둔
/// 값"처럼 저장소 API로는 만들 수 없는 상태를 만들 때 쓴다.
private func rawContainer(at url: URL) throws -> ModelContainer {
    try ModelContainer(
        for: testSchema,
        configurations: [ModelConfiguration(schema: testSchema, url: url)]
    )
}

private func makeSession(
    startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    situation: CaptureSituation = .rally,
    swingKinds: [SwingKind?] = [.forehand, nil],
    clipOffsets: [TimeInterval] = [5]
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
        clips: clipOffsets.enumerated().map { index, offset in
            Clip(
                fileName: "clip-\(index).mov",
                recordedAt: startedAt.addingTimeInterval(offset),
                fps: 120,
                // 스윙은 첫 클립에만 둔다. 클립 수를 늘려도 스윙 수 단언이
                // 흔들리지 않게 한다.
                swings: index == 0 ? swings : []
            )
        }
    )
}

@Suite("SwiftDataSessionRepository")
struct SwiftDataSessionRepositoryTests {

    // MARK: - 왕복

    /// ⚠️ **새 컨테이너에서 읽는다.** 같은 컨테이너에서 읽으면 메모리
    /// 캐시를 보게 되어 디스크에 실제로 쓰였는지 확인되지 않는다.
    /// 근거: SPEC-0070 검증 방법
    @Test("저장한 세션을 새 컨테이너에서 읽으면 같다")
    func 왕복() async throws {
        let store = TempStore()
        let session = makeSession()

        let writer = try SwiftDataSessionRepository(storeURL: store.url)
        try await writer.save(session)

        let reader = try SwiftDataSessionRepository(storeURL: store.url)
        let loaded = try #require(try await reader.load(id: session.id))

        #expect(loaded == session)
    }

    @Test("클립과 스윙이 함께 왕복한다")
    func 중첩_왕복() async throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [.serve, .backhand, nil])

        try await SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.clips.count == 1)
        #expect(loaded.swingCount == 3)
        #expect(loaded.clips[0].swings.map(\.kind) == [.serve, .backhand, nil])
    }

    @Test("아직 분류되지 않은 스윙은 kind가 nil로 남는다")
    func 미분류_스윙() async throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [nil])

        try await SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.clips[0].swings[0].kind == nil)
    }

    @Test("없는 id를 읽으면 nil이다")
    func 없는_세션() async throws {
        let store = TempStore()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        #expect(try await repository.load(id: UUID()) == nil)
    }

    @Test("같은 id로 다시 저장하면 갈아끼운다")
    func 덮어쓰기() async throws {
        let store = TempStore()
        var session = makeSession()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try await repository.save(session)

        session.clips[0].fileName = "clip-renamed.mov"
        try await repository.save(session)

        #expect(try await repository.loadAll().count == 1)
        let counts = try rowCounts(at: store.url)
        #expect(counts.clips == 1, "덮어쓰기가 옛 클립을 남기면 고아 행이 쌓인다")
        // 클립만 세면 스윙 cascade만 놓치는 변이가 통과한다. 삭제 경로는
        // cascade_삭제가 덮지만 덮어쓰기 경로는 여기서만 확인된다.
        #expect(counts.swings == 2, "덮어쓰기가 옛 스윙을 남기면 고아 행이 쌓인다")
        #expect(
            try await SwiftDataSessionRepository(storeURL: store.url)
                .load(id: session.id)?.clips[0].fileName == "clip-renamed.mov"
        )
    }

    @Test("최근 세션이 먼저 나온다")
    func 정렬() async throws {
        let store = TempStore()
        let old = makeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        let new = makeSession(startedAt: Date(timeIntervalSince1970: 2_000))
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try await repository.save(old)
        try await repository.save(new)

        #expect(try await repository.loadAll().map(\.id) == [new.id, old.id])
    }

    /// SwiftData의 to-many 관계는 **순서를 보장하지 않는다.** 정렬이 없으면
    /// 보관함의 클립 목록이 실행할 때마다 달라진다.
    ///
    /// ⚠️ 입력을 **역순**으로 넣는다. 정순으로 넣으면 "정렬했다"와
    /// "받은 순서를 그대로 돌려줬다"가 구별되지 않아, 정렬을 지워도 통과한다.
    @Test("여러 클립은 촬영 시각 순으로 돌아온다")
    func 클립_정렬() async throws {
        let store = TempStore()
        let session = makeSession(clipOffsets: [120, 5, 60])

        try await SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        // 입력은 clip-0(120초) · clip-1(5초) · clip-2(60초) 순이었다.
        #expect(loaded.clips.map(\.fileName) == ["clip-1.mov", "clip-2.mov", "clip-0.mov"])
    }

    // MARK: - cascade

    /// 이 테스트는 **행을 직접 센다.** `loadAll()`이 0을 준다고 해서
    /// 클립·스윙 행이 지워졌다는 뜻은 아니다 — 세션만 지우고 고아가
    /// 남아도 저장소 API로는 똑같이 보인다.
    @Test("세션을 지우면 클립과 스윙도 지워진다")
    func cascade_삭제() async throws {
        let store = TempStore()
        let session = makeSession(swingKinds: [.forehand, .backhand])
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try await repository.save(session)

        let before = try rowCounts(at: store.url)
        #expect(before == (sessions: 1, clips: 1, swings: 2))

        try await repository.delete(id: session.id)

        let after = try rowCounts(at: store.url)
        #expect(after == (sessions: 0, clips: 0, swings: 0))
    }

    @Test("없는 id를 지우면 아무 일도 없다")
    func 없는_세션_삭제() async throws {
        let store = TempStore()
        let session = makeSession()
        let repository = try SwiftDataSessionRepository(storeURL: store.url)
        try await repository.save(session)

        try await repository.delete(id: UUID())

        #expect(try await repository.loadAll().count == 1)
    }

    // MARK: - 상황 보존

    @Test("상황과 관찰 대상이 그대로 돌아온다", arguments: CaptureSituation.allCases)
    func 상황_왕복(_ situation: CaptureSituation) async throws {
        let store = TempStore()
        let session = makeSession(situation: situation)

        try await SwiftDataSessionRepository(storeURL: store.url).save(session)
        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: session.id)
        )

        #expect(loaded.situation == situation)
        #expect(loaded.observable == session.observable)
    }

    // MARK: - 알 수 없는 raw 값

    /// 저장소 API로는 만들 수 없는 상태다 — 행을 직접 쓴다. "앞선 버전이
    /// 쓴 값을 현재 enum이 모른다"는 상황을 흉내 낸다.
    ///
    /// 두 필드가 **따로** 폴백하면 도메인이 불가능하다고 선언한 조합이
    /// 만들어진다. `situationRaw`만 모르는 값이면 `.rally`로 떨어지는데
    /// `observableRaw`는 `lineCall` 그대로 살아남아, `allowsLineCall`이
    /// 거짓인 상황에 라인 판정이 붙는다.
    @Test("모르는 상황 raw는 기본값으로 떨어지고 관찰 대상도 함께 맞춰진다")
    func 알_수_없는_상황_폴백() async throws {
        let store = TempStore()
        let id = UUID()

        let context = ModelContext(try rawContainer(at: store.url))
        context.insert(SessionModel(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            situationRaw: "doubles",     // 현재 enum에 없다
            observableRaw: "lineCall",   // 현재 enum에 있다
            fps: 120
        ))
        try context.save()

        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: id)
        )

        #expect(loaded.situation == .rally)
        #expect(
            loaded.observable == .swing,
            "랠리는 라인 판정을 허용하지 않는다 — 폴백이 따로 일어나면 불가능한 조합이 된다"
        )
    }

    @Test("모르는 관찰 대상 raw는 .swing으로 떨어진다")
    func 알_수_없는_관찰_대상_폴백() async throws {
        let store = TempStore()
        let id = UUID()

        let context = ModelContext(try rawContainer(at: store.url))
        context.insert(SessionModel(
            id: id,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            situationRaw: "match",
            observableRaw: "netCord",    // 현재 enum에 없다
            fps: 120
        ))
        try context.save()

        let loaded = try #require(
            try await SwiftDataSessionRepository(storeURL: store.url).load(id: id)
        )

        #expect(loaded.situation == .match)
        #expect(loaded.observable == .swing)
    }
}
