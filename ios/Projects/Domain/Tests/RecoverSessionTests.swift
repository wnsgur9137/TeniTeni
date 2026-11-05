import Foundation
import Testing
@testable import Domain

private func did(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

private let start = Date(timeIntervalSince1970: 1_700_000_000)
private let recoveredAt = Date(timeIntervalSince1970: 1_700_009_999)

/// 호출 순서를 기록하는 가짜들. **순서가 폐기의 핵심이다** —
/// `DeleteSessionTests`와 같은 방식이다.
private actor Journal {
    private(set) var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
}

private struct SpyFileStore: ClipFileStore {
    let journal: Journal
    func remove(fileName: String) async { await journal.add("file:\(fileName)") }
}

private struct SpyRepository: SessionRepository, Sendable {
    let journal: Journal
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

/// 디스크에 있다고 **주장하는** 것. 실제 `.mov`가 필요 없다 —
/// `OrphanClipStore`를 추상으로 가른 이유가 이것이다.
private struct StubOrphans: OrphanClipStore {
    let found: [OrphanClip]
    func orphans(for session: Session) async -> [OrphanClip] { found }
}

private func orphan(_ index: Int, fps: Int = 120, offset: Double = 0) -> OrphanClip {
    OrphanClip(
        fileName: "20231114-221320-\(index).mov",
        index: index,
        recordedAt: start.addingTimeInterval(offset),
        fps: fps
    )
}

/// 끝나지 않은 세션. **`endedAt`이 없다** — 촬영 시작 시 레코드를 열기
/// 때문에 생기는 상태다.
private func unfinished(clips: [Clip] = []) -> Session {
    Session(
        id: did(0),
        startedAt: start,
        endedAt: nil,
        situation: .ballMachine,
        observable: .swing,
        fps: 120,
        clips: clips
    )
}

/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 4
@Suite("세션 복구")
struct RecoverSessionUseCaseTests {

    private func useCase(_ journal: Journal, _ found: [OrphanClip]) -> RecoverSessionUseCase {
        RecoverSessionUseCase(
            repository: SpyRepository(journal: journal),
            orphans: StubOrphans(found: found)
        )
    }

    @Test("고아 클립을 index 순서로 붙이고 세션을 닫는다")
    func 복구() async throws {
        let journal = Journal()
        // **일부러 거꾸로 준다.** 정렬하지 않으면 이 테스트가 잡는다.
        let found = [orphan(2, offset: 40), orphan(0, offset: 0), orphan(1, offset: 20)]

        let outcome = try await useCase(journal, found).execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다: \(outcome)")
            return
        }
        #expect(session.clips.map(\.fileName) == [
            "20231114-221320-0.mov",
            "20231114-221320-1.mov",
            "20231114-221320-2.mov",
        ])
        #expect(session.recoveredAt == recoveredAt)
        #expect(await journal.entries == ["save:3"])
    }

    /// ⚠️ `now`를 쓰면 **어제 죽은 세션의 `duration`이 하루가 된다.**
    /// 보관함과 세션 비교가 그 값을 읽는다.
    @Test("endedAt은 마지막 클립 시각이다 — now가 아니다")
    func 종료_시각() async throws {
        let journal = Journal()
        let found = [orphan(0, offset: 0), orphan(1, offset: 20), orphan(2, offset: 40)]

        let outcome = try await useCase(journal, found).execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(session.endedAt == start.addingTimeInterval(40))
        #expect(session.duration == 40)
    }

    /// 전부 같은 시각이면 **보관함·리플레이 정렬이 무의미해진다.**
    @Test("클립마다 recordedAt이 다르다")
    func 클립_시각() async throws {
        let journal = Journal()
        let found = [orphan(0, offset: 0), orphan(1, offset: 20), orphan(2, offset: 40)]

        let outcome = try await useCase(journal, found).execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(Set(session.clips.map(\.recordedAt)).count == 3)
    }

    /// 세션의 fps를 그대로 쓰면 발열 강등을 걸친 세션이 틀어진다(ADR-0005).
    @Test("클립 fps는 파일에서 온 값을 쓴다")
    func 클립_fps() async throws {
        let journal = Journal()
        // 세션은 120인데 강등 뒤 클립은 60이다.
        let found = [orphan(0, fps: 120), orphan(1, fps: 60)]

        let outcome = try await useCase(journal, found).execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(session.clips.map(\.fps) == [120, 60])
    }

    /// 스윙 구간은 비운다 — 고아 클립에 사이드카가 없다(#121).
    @Test("복구한 클립의 스윙은 0개다")
    func 스윙_없음() async throws {
        let journal = Journal()
        let outcome = try await useCase(journal, [orphan(0)]).execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(session.swingCount == 0)
        // ★ 그런데 **진단 화면으로 가지 않는다.** `recoveredAt`이 가른다.
        #expect(session.needsDiagnosis == false)
    }

    /// 첫 프레임이 오기 전에 죽은 세션이다. 저장하지 않는다.
    @Test("영상이 하나도 없으면 복구하지 않는다")
    func 영상_없음() async throws {
        let journal = Journal()
        let outcome = try await useCase(journal, []).execute(unfinished(), now: recoveredAt)

        #expect(outcome == .nothingToRecover)
        #expect(await journal.entries.isEmpty)
    }

    /// 덮으면 멀쩡한 `endedAt`을 추정값으로 바꾼다.
    @Test("이미 닫힌 세션은 건드리지 않는다")
    func 닫힌_세션() async throws {
        let journal = Journal()
        let closed = Session(
            id: did(0), startedAt: start, endedAt: start.addingTimeInterval(300),
            situation: .ballMachine, fps: 120,
            clips: [Clip(fileName: "a.mov", recordedAt: start, fps: 120)]
        )

        let outcome = try await useCase(journal, [orphan(9)]).execute(closed, now: recoveredAt)

        #expect(outcome == .recovered(closed))
        #expect(await journal.entries.isEmpty)
    }

    /// 레코드에 이미 담긴 클립을 또 붙이면 **같은 파일이 두 줄**이 된다.
    @Test("레코드에 있던 클립 뒤에 붙인다")
    func 기존_클립() async throws {
        let journal = Journal()
        let existing = Clip(id: did(50), fileName: "old.mov", recordedAt: start, fps: 120)

        let outcome = try await useCase(journal, [orphan(0)])
            .execute(unfinished(clips: [existing]), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(session.clips.map(\.fileName) == ["old.mov", "20231114-221320-0.mov"])
    }
}

/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 5
@Suite("세션 폐기")
struct DiscardSessionUseCaseTests {

    private func useCase(
        _ journal: Journal, _ found: [OrphanClip], deleteFails: Bool = false
    ) -> DiscardSessionUseCase {
        DiscardSessionUseCase(
            repository: SpyRepository(journal: journal, deleteFails: deleteFails),
            files: SpyFileStore(journal: journal),
            orphans: StubOrphans(found: found)
        )
    }

    /// ⚠️ **순서가 "남는 상태"를 정한다** — #126과 같은 결정이다.
    @Test("파일을 먼저, 레코드를 나중에 지운다")
    func 순서() async throws {
        let journal = Journal()
        try await useCase(journal, [orphan(0), orphan(1)]).execute(unfinished())

        #expect(await journal.entries == [
            "file:20231114-221320-0.mov",
            "file:20231114-221320-1.mov",
            "record",
        ])
    }

    /// ⚠️ **`DeleteSessionUseCase`를 그대로 쓰면 이것이 남는다.** 그쪽은
    /// 레코드의 `clips`를 도는데, 미완 세션의 레코드에는 클립이 0개다.
    @Test("레코드가 모르는 고아 파일도 지운다")
    func 고아_파일() async throws {
        let journal = Journal()
        // 레코드의 클립은 0개다.
        try await useCase(journal, [orphan(0), orphan(1), orphan(2)]).execute(unfinished())

        let entries = await journal.entries
        #expect(entries.filter { $0.hasPrefix("file:") }.count == 3)
    }

    /// 어느 한쪽만 보면 남는 것이 생긴다.
    @Test("레코드가 아는 것과 디스크에만 있는 것을 모두 지운다")
    func 합집합() async throws {
        let journal = Journal()
        let known = Clip(fileName: "known.mov", recordedAt: start, fps: 120)

        try await useCase(journal, [orphan(0)]).execute(unfinished(clips: [known]))

        #expect(await journal.entries == [
            "file:known.mov",
            "file:20231114-221320-0.mov",
            "record",
        ])
    }

    /// 같은 파일을 두 번 지우려 들면 두 번째는 "없는 파일"이 된다 —
    /// 실패는 아니지만 호출이 낭비되고 로그가 지저분해진다.
    @Test("레코드와 디스크에 겹치는 파일은 한 번만 지운다")
    func 중복() async throws {
        let journal = Journal()
        let known = Clip(fileName: "20231114-221320-0.mov", recordedAt: start, fps: 120)

        try await useCase(journal, [orphan(0)]).execute(unfinished(clips: [known]))

        #expect(await journal.entries == ["file:20231114-221320-0.mov", "record"])
    }

    /// ⚠️ 확인 문구가 이 값을 적는다. `session.clips.count`를 쓰면
    /// **미완 세션에서 항상 0**이고, #126이 세운 근거가 무너진다.
    @Test("지울 클립 수는 스캔 결과다")
    func 클립_수() async throws {
        let journal = Journal()
        let found = [orphan(0), orphan(1), orphan(2)]

        let count = await useCase(journal, found).clipCount(unfinished())

        #expect(count == 3)
        // 레코드만 보면 0이다. 이것이 함정이었다.
        #expect(unfinished().clips.count == 0)
    }

    @Test("레코드 삭제가 실패해도 파일은 지워진 상태다")
    func 레코드_실패() async {
        let journal = Journal()
        let useCase = useCase(journal, [orphan(0)], deleteFails: true)

        await #expect(throws: SpyRepository.Boom.self) {
            try await useCase.execute(unfinished())
        }
        #expect(await journal.entries == ["file:20231114-221320-0.mov", "record"])
    }
}

@Suite("끝나지 않은 세션의 판정")
struct UnfinishedSessionTests {

    @Test("endedAt이 없으면 끝나지 않은 세션이다")
    func 판정() {
        #expect(unfinished().isUnfinished)
        #expect(unfinished().duration == nil)
    }

    /// ⚠️ **이것이 이 이슈의 핵심 분기다.** 둘 다 스윙 0개인데 뜻이 다르다.
    @Test("복구된 세션은 스윙 0개여도 진단이 아니다")
    func 진단_분기() {
        let notAnalyzed = Session(
            startedAt: start, endedAt: start.addingTimeInterval(60),
            recoveredAt: recoveredAt, situation: .wall, fps: 120,
            clips: [Clip(fileName: "a.mov", recordedAt: start, fps: 120)]
        )
        let notFound = Session(
            startedAt: start, endedAt: start.addingTimeInterval(60),
            situation: .wall, fps: 120,
            clips: [Clip(fileName: "a.mov", recordedAt: start, fps: 120)]
        )

        #expect(notAnalyzed.swingCount == 0)
        #expect(notFound.swingCount == 0)
        // 분석하지 않은 것 ≠ 못 찾은 것.
        #expect(notAnalyzed.needsDiagnosis == false)
        #expect(notFound.needsDiagnosis)
    }

    @Test("스윙이 있으면 복구 여부와 무관하게 진단이 아니다")
    func 스윙_있음() {
        let session = Session(
            startedAt: start, endedAt: start.addingTimeInterval(60),
            recoveredAt: recoveredAt, situation: .wall, fps: 120,
            clips: [Clip(
                fileName: "a.mov", recordedAt: start, fps: 120,
                swings: [Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5)]
            )]
        )
        #expect(session.needsDiagnosis == false)
    }
}
