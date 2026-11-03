import Foundation
import Testing
@testable import Domain

private func did(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

/// 호출 순서를 기록하는 가짜들. **순서가 이 작업의 핵심이다** —
/// 어느 쪽이 먼저냐가 "실패했을 때 남는 상태"를 정한다.
private actor Journal {
    private(set) var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

private struct SpyFileStore: ClipFileStore {
    let journal: Journal
    func remove(fileName: String) async {
        await journal.add("file:\(fileName)")
    }
}

private struct SpyRepository: SessionRepository, Sendable {
    let journal: Journal
    /// 레코드 삭제가 실패한다. **파일은 이미 지워진 상태여야 한다.**
    let deleteFails: Bool

    struct Boom: LocalizedError, Equatable {
        var errorDescription: String? { "디스크를 쓸 수 없습니다" }
    }

    init(journal: Journal, deleteFails: Bool = false) {
        self.journal = journal
        self.deleteFails = deleteFails
    }

    func save(_ session: Session) async throws {
        await journal.add("save:\(session.clips.count)")
    }
    func load(id: UUID) async throws -> Session? { nil }
    func loadAll() async throws -> [Session] { [] }

    func delete(id: UUID) async throws {
        await journal.add("record")
        if deleteFails { throw Boom() }
    }
}

private func session(clipCount: Int, swingsPerClip: Int = 2) -> Session {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return Session(
        id: did(0),
        startedAt: start,
        situation: .ballMachine,
        fps: 120,
        clips: (0..<clipCount).map { index in
            Clip(
                id: did(10 + index),
                fileName: "clip-\(index).mov",
                recordedAt: start.addingTimeInterval(Double(index) * 10),
                fps: 120,
                swings: (0..<swingsPerClip).map { swing in
                    Swing(
                        id: did(100 + index * 10 + swing),
                        startSeconds: 1, endSeconds: 3, impactSeconds: 2
                    )
                }
            )
        }
    )
}

/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 2·4
@Suite("세션 삭제")
struct DeleteSessionUseCaseTests {

    /// ⚠️ **순서가 "남는 상태"를 정한다.**
    ///
    /// 레코드를 먼저 지우면 실패 시 **보이지 않는** 고아 `.mov`가 남고,
    /// 파일을 먼저 지우면 **#120이 "영상이 없습니다"로 보여주는** 빈
    /// 레코드가 남는다. 보이지 않는 쓰레기보다 보이는 빈 껍데기가 낫다.
    @Test("파일을 먼저, 레코드를 나중에 지운다")
    func 순서() async throws {
        let journal = Journal()
        let useCase = DeleteSessionUseCase(
            repository: SpyRepository(journal: journal),
            files: SpyFileStore(journal: journal)
        )
        try await useCase.execute(session(clipCount: 2))

        #expect(await journal.entries == ["file:clip-0.mov", "file:clip-1.mov", "record"])
    }

    /// 되돌리려면 지운 파일을 복원해야 하는데 우리는 그것을 들고 있지 않다.
    @Test("레코드 삭제가 실패해도 파일은 지워진 상태다")
    func 레코드_실패() async {
        let journal = Journal()
        let useCase = DeleteSessionUseCase(
            repository: SpyRepository(journal: journal, deleteFails: true),
            files: SpyFileStore(journal: journal)
        )
        await #expect(throws: SpyRepository.Boom.self) {
            try await useCase.execute(session(clipCount: 2))
        }
        // 파일은 이미 지워졌다. 되돌리지 않는다.
        #expect(await journal.entries == ["file:clip-0.mov", "file:clip-1.mov", "record"])
    }

    @Test("클립이 없는 세션도 레코드를 지운다")
    func 클립_0개() async throws {
        let journal = Journal()
        let useCase = DeleteSessionUseCase(
            repository: SpyRepository(journal: journal),
            files: SpyFileStore(journal: journal)
        )
        try await useCase.execute(session(clipCount: 0))
        #expect(await journal.entries == ["record"])
    }
}

@Suite("클립 삭제")
struct DeleteClipUseCaseTests {

    @Test("클립 하나를 지우면 파일을 먼저 지우고 세션을 다시 쓴다")
    func 클립만() async throws {
        let journal = Journal()
        let useCase = DeleteClipUseCase(
            repository: SpyRepository(journal: journal),
            files: SpyFileStore(journal: journal)
        )
        let outcome = try await useCase.execute(session(clipCount: 3), clipID: did(11))

        #expect(outcome == .clipRemoved)
        // 파일 먼저, 그다음 남은 2개로 세션을 다시 쓴다.
        #expect(await journal.entries == ["file:clip-1.mov", "save:2"])
    }

    /// ⚠️ **빈 세션을 남기면 #120이 만든 "영상이 없습니다" 행이 두 가지를
    /// 뜻하게 된다** — 파일이 사라졌거나, 내가 지웠거나. 구분하려면
    /// 레코드 필드와 화면 상태가 하나씩 늘어난다.
    @Test("마지막 클립을 지우면 세션도 지운다")
    func 마지막_클립() async throws {
        let journal = Journal()
        let useCase = DeleteClipUseCase(
            repository: SpyRepository(journal: journal),
            files: SpyFileStore(journal: journal)
        )
        let outcome = try await useCase.execute(session(clipCount: 1), clipID: did(10))

        #expect(outcome == .sessionRemoved)
        // 세션을 다시 쓰지 않는다 — 지운다.
        #expect(await journal.entries == ["file:clip-0.mov", "record"])
    }

    /// 이미 지워졌을 수 있다. 결과는 같다: 그 클립은 없다.
    @Test("없는 클립을 지우라고 하면 파일을 건드리지 않는다")
    func 없는_클립() async throws {
        let journal = Journal()
        let useCase = DeleteClipUseCase(
            repository: SpyRepository(journal: journal),
            files: SpyFileStore(journal: journal)
        )
        let outcome = try await useCase.execute(session(clipCount: 2), clipID: did(999))

        #expect(outcome == .clipRemoved)
        #expect(await journal.entries.isEmpty)
    }

    @Test("레코드 갱신이 실패해도 파일은 지워진 상태다")
    func 갱신_실패() async {
        let journal = Journal()
        let useCase = DeleteClipUseCase(
            repository: SpyRepository(journal: journal, deleteFails: true),
            files: SpyFileStore(journal: journal)
        )
        // 마지막 클립이면 `delete`를 타므로 실패한다.
        await #expect(throws: SpyRepository.Boom.self) {
            _ = try await useCase.execute(session(clipCount: 1), clipID: did(10))
        }
        #expect(await journal.entries == ["file:clip-0.mov", "record"])
    }
}
