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

/// ⚠️ **`load`가 실제로 읽는다.** 유스케이스가 실행 직전에 레코드를 다시
/// 읽기 때문이다 — 확인을 띄운 사이에 세션이 바뀌면 들고 있던 스냅샷으로
/// 저장하면 안 된다. `nil`을 주는 가짜를 쓰면 그 경로가 검증되지 않는다.
private actor SpyRepository: SessionRepository {
    let journal: Journal
    let deleteFails: Bool
    private var stored: [UUID: Session]

    struct Boom: LocalizedError, Equatable {
        var errorDescription: String? { "디스크를 쓸 수 없습니다" }
    }

    init(journal: Journal, stored: [Session] = [], deleteFails: Bool = false) {
        self.journal = journal
        self.deleteFails = deleteFails
        self.stored = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
    }

    func save(_ session: Session) async throws {
        await journal.add("save:\(session.clips.count)")
        stored[session.id] = session
    }
    func load(id: UUID) async throws -> Session? { stored[id] }
    func loadAll() async throws -> [Session] { Array(stored.values) }
    func delete(id: UUID) async throws {
        await journal.add("record")
        if deleteFails { throw Boom() }
        stored[id] = nil
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

    /// `stored`를 명시하지 않으면 **인자로 넘기는 세션이 저장소에도 있다고**
    /// 둔다. 유스케이스가 실행 직전 다시 읽기 때문이다.
    private func useCase(
        _ journal: Journal, _ found: [OrphanClip], stored: [Session]? = nil
    ) -> RecoverSessionUseCase {
        RecoverSessionUseCase(
            repository: SpyRepository(journal: journal, stored: stored ?? [unfinished()]),
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

        let outcome = try await useCase(journal, [orphan(9)], stored: [closed])
            .execute(closed, now: recoveredAt)

        #expect(outcome == .recovered(closed))
        #expect(await journal.entries.isEmpty)
    }

    /// 레코드에 이미 담긴 클립을 또 붙이면 **같은 파일이 두 줄**이 된다.
    @Test("레코드에 있던 클립 뒤에 붙인다")
    func 기존_클립() async throws {
        let journal = Journal()
        let existing = Clip(id: did(50), fileName: "old.mov", recordedAt: start, fps: 120)
        let withClip = unfinished(clips: [existing])

        let outcome = try await useCase(journal, [orphan(0)], stored: [withClip])
            .execute(withClip, now: recoveredAt)

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
        _ journal: Journal, _ found: [OrphanClip],
        stored: [Session]? = nil, deleteFails: Bool = false
    ) -> DiscardSessionUseCase {
        DiscardSessionUseCase(
            repository: SpyRepository(
                journal: journal, stored: stored ?? [unfinished()], deleteFails: deleteFails
            ),
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
        let withClip = unfinished(clips: [known])

        try await useCase(journal, [orphan(0)], stored: [withClip]).execute(withClip)

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
        let withClip = unfinished(clips: [known])

        try await useCase(journal, [orphan(0)], stored: [withClip]).execute(withClip)

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
        let useCase = useCase(journal, [orphan(0)], stored: nil, deleteFails: true)

        await #expect(throws: SpyRepository.Boom.self) {
            try await useCase.execute(unfinished())
        }
        #expect(await journal.entries == ["file:20231114-221320-0.mov", "record"])
    }
}

/// 독립 리뷰가 찾은 경로들. **전부 "확인을 띄운 뒤 세계가 바뀐다"는
/// 한 가지 성질에서 나온다.**
///
/// 근거: PR #145 리뷰
@Suite("복구·폐기 — 확인 뒤에 바뀐 상태")
struct StaleStateTests {

    /// ⚠️ 들고 있던 스냅샷으로 저장하면 **분석이 끝난 세션의 `endedAt`과
    /// 스윙이 추정값으로 덮인다.** #126이 삭제에서 세운 "확인 뒤 다시
    /// 찾는다"와 같은 이유다.
    @Test("확인하는 사이에 세션이 닫혔으면 복구가 덮지 않는다")
    func 복구_중_닫힘() async throws {
        let journal = Journal()
        let snapshot = unfinished()
        // 저장소에는 **이미 닫힌** 세션이 있다.
        let closed = Session(
            id: did(0), startedAt: start, endedAt: start.addingTimeInterval(300),
            situation: .ballMachine, fps: 120,
            clips: [Clip(
                fileName: "real.mov", recordedAt: start, fps: 120,
                swings: [Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5)]
            )]
        )
        let useCase = RecoverSessionUseCase(
            repository: SpyRepository(journal: journal, stored: [closed]),
            orphans: StubOrphans(found: [orphan(0)])
        )

        let outcome = try await useCase.execute(snapshot, now: recoveredAt)

        #expect(outcome == .recovered(closed))
        // 저장하지 않았다 — 스윙이 살아 있다.
        #expect(await journal.entries.isEmpty)
    }

    /// 사용자가 다른 경로로 지웠다는 뜻이다. 되살리면 지운 것이 돌아온다.
    @Test("레코드가 사라졌으면 되살리지 않는다")
    func 복구_중_삭제() async throws {
        let journal = Journal()
        let useCase = RecoverSessionUseCase(
            repository: SpyRepository(journal: journal, stored: []),
            orphans: StubOrphans(found: [orphan(0)])
        )

        let outcome = try await useCase.execute(unfinished(), now: recoveredAt)

        #expect(outcome == .nothingToRecover)
        #expect(await journal.entries.isEmpty)
    }

    /// ⚠️ **되돌릴 수 없다.** 분석이 끝난 스윙과 그 영상이 사라진다.
    @Test("확인하는 사이에 세션이 닫혔으면 폐기하지 않는다")
    func 폐기_중_닫힘() async throws {
        let journal = Journal()
        let closed = Session(
            id: did(0), startedAt: start, endedAt: start.addingTimeInterval(300),
            situation: .ballMachine, fps: 120,
            clips: [Clip(fileName: "real.mov", recordedAt: start, fps: 120)]
        )
        let useCase = DiscardSessionUseCase(
            repository: SpyRepository(journal: journal, stored: [closed]),
            files: SpyFileStore(journal: journal),
            orphans: StubOrphans(found: [orphan(0)])
        )

        let outcome = try await useCase.execute(unfinished())

        #expect(outcome == .alreadyClosed)
        // 파일도 레코드도 건드리지 않았다.
        #expect(await journal.entries.isEmpty)
    }

    /// 파일명 접두사는 **초 단위**다(`"yyyyMMdd-HHmmss"`). 같은 초에 시작한
    /// 두 세션은 접두사를 공유하고, 그러면 한쪽의 클립을 다른 쪽이 가져가
    /// **원래 세션에서 조용히 사라진다.**
    @Test("다른 세션이 아는 파일은 복구가 가져가지 않는다")
    func 접두사_충돌_복구() async throws {
        let journal = Journal()
        let mine = unfinished()
        // 같은 접두사의 파일을 **다른 세션이** 이미 들고 있다.
        let other = Session(
            id: did(1), startedAt: start, endedAt: start.addingTimeInterval(60),
            situation: .rally, fps: 120,
            clips: [Clip(fileName: "20231114-221320-1.mov", recordedAt: start, fps: 120)]
        )
        let useCase = RecoverSessionUseCase(
            repository: SpyRepository(journal: journal, stored: [mine, other]),
            orphans: StubOrphans(found: [orphan(0), orphan(1)])
        )

        let outcome = try await useCase.execute(mine, now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        // 1번은 남의 것이다.
        #expect(session.clips.map(\.fileName) == ["20231114-221320-0.mov"])
    }

    /// ⚠️ 지우면 **사용자가 폐기하지 않은 영상이 사라진다.**
    @Test("다른 세션이 아는 파일은 폐기가 지우지 않는다")
    func 접두사_충돌_폐기() async throws {
        let journal = Journal()
        let mine = unfinished()
        let other = Session(
            id: did(1), startedAt: start, endedAt: start.addingTimeInterval(60),
            situation: .rally, fps: 120,
            clips: [Clip(fileName: "20231114-221320-1.mov", recordedAt: start, fps: 120)]
        )
        let useCase = DiscardSessionUseCase(
            repository: SpyRepository(journal: journal, stored: [mine, other]),
            files: SpyFileStore(journal: journal),
            orphans: StubOrphans(found: [orphan(0), orphan(1)])
        )

        try await useCase.execute(mine)

        #expect(await journal.entries == ["file:20231114-221320-0.mov", "record"])
    }

    /// 파일 시각은 파일시스템 시계, 세션 시작은 벽시계다. 기기 시각이
    /// 조정되면 클립이 세션보다 **이르게** 찍히고 `duration`이 음수가 된다.
    @Test("endedAt은 startedAt보다 이를 수 없다")
    func 시각_역전() async throws {
        let journal = Journal()
        // 클립이 세션 시작 **10분 전**으로 찍혔다.
        let earlier = OrphanClip(
            fileName: "20231114-221320-0.mov", index: 0,
            recordedAt: start.addingTimeInterval(-600), fps: 120
        )
        let useCase = RecoverSessionUseCase(
            repository: SpyRepository(journal: journal, stored: [unfinished()]),
            orphans: StubOrphans(found: [earlier])
        )

        let outcome = try await useCase.execute(unfinished(), now: recoveredAt)

        guard case .recovered(let session) = outcome else {
            Issue.record("복구되지 않았다"); return
        }
        #expect(session.endedAt == start)
        let duration = try #require(session.duration)
        #expect(duration >= 0, "duration이 음수다: \(duration)")
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
