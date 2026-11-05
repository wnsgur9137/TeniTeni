import ComposableArchitecture
import Domain
import Foundation
import Synchronization
import Testing
@testable import Presentation

private func rid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

private let start = Date(timeIntervalSince1970: 1_700_000_000)
private let fixedNow = Date(timeIntervalSince1970: 1_700_009_999)

private final class MutableRepository: SessionRepository, Sendable {
    private let stored: Mutex<[Session]>

    init(_ initial: [Session]) { self.stored = Mutex(initial) }

    var sessions: [Session] { stored.withLock { $0 } }

    func save(_ session: Session) async throws {
        stored.withLock {
            $0.removeAll { $0.id == session.id }
            $0.append(session)
        }
    }
    func load(id: UUID) async throws -> Session? { sessions.first { $0.id == id } }
    func loadAll() async throws -> [Session] { sessions }
    func delete(id: UUID) async throws {
        stored.withLock { $0.removeAll { $0.id == id } }
    }
}

private actor RemovalLog {
    private(set) var removed: [String] = []
    func add(_ name: String) { removed.append(name) }
}

private struct SpyFiles: ClipFileStore {
    let log: RemovalLog
    func remove(fileName: String) async { await log.add(fileName) }
}

private struct StubOrphans: OrphanClipStore {
    let found: [OrphanClip]
    func orphans(for session: Session) async -> [OrphanClip] { found }
}

private func orphan(_ index: Int, offset: Double) -> OrphanClip {
    OrphanClip(
        fileName: "clip-\(index).mov",
        index: index,
        recordedAt: start.addingTimeInterval(offset),
        fps: 120
    )
}

/// 끝나지 않은 세션. **레코드의 클립은 0개다** — 촬영 중에는 레코드를
/// 갱신하지 않는다.
private func unfinished(id: UUID = rid(0), dayOffset: Int = 0) -> Session {
    Session(
        id: id,
        startedAt: start.addingTimeInterval(Double(dayOffset) * 86_400),
        endedAt: nil,
        situation: .ballMachine,
        observable: .swing,
        fps: 120,
        clips: []
    )
}

private func finished(id: UUID, dayOffset: Int) -> Session {
    let s = start.addingTimeInterval(Double(dayOffset) * 86_400)
    return Session(
        id: id,
        startedAt: s,
        endedAt: s.addingTimeInterval(120),
        situation: .rally,
        fps: 120,
        clips: [Clip(
            fileName: "done-\(dayOffset).mov", recordedAt: s, fps: 120,
            swings: [Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5)]
        )]
    )
}

private let presentLocator = ClipLocator(directory: URL(filePath: "/clips")) { _ in true }

/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 6
@Suite("보관함 — 끝나지 않은 세션")
@MainActor
struct RecoverFlowTests {

    private func makeStore(
        _ sessions: [Session],
        orphans: [OrphanClip] = [orphan(0, offset: 0)],
        log: RemovalLog = RemovalLog(),
        repository: MutableRepository? = nil
    ) -> (TestStoreOf<LibraryFeature>, MutableRepository, RemovalLog) {
        let repo = repository ?? MutableRepository(sessions)
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(
                repository: repo,
                locator: presentLocator,
                files: SpyFiles(log: log),
                orphans: StubOrphans(found: orphans),
                now: { fixedNow }
            )
        }
        store.exhaustivity = .off
        return (store, repo, log)
    }

    /// ★ 요약으로 보내지 않는다 — 보여줄 클립이 레코드에 없다.
    @Test("미완 세션 행을 누르면 복구 시트가 뜬다")
    func 시트() async {
        let (store, _, _) = makeStore([unfinished()])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        await store.send(.sessionTapped(rid(0)))
        await store.receive(\.recoverRequested)

        let target = store.state.recovering
        #expect(target?.sessionID == rid(0))
        // 상황과 fps가 **레코드에서** 온다.
        #expect(target?.situationText == "볼머신 · 내 스윙")
        #expect(target?.fpsText == "120fps")
    }

    /// 정상 세션은 그대로 요약으로 간다.
    @Test("끝난 세션은 요약으로 간다")
    func 회귀() async {
        let (store, _, _) = makeStore([finished(id: rid(1), dayOffset: 0)])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        await store.send(.sessionTapped(rid(1)))
        await store.receive(\.delegate)
        #expect(store.state.recovering == nil)
    }

    /// ⚠️ 레코드의 `clips.count`를 쓰면 **항상 0**이다.
    @Test("시트의 클립 수는 디스크 스캔 결과다")
    func 클립_수() async {
        let (store, _, _) = makeStore(
            [unfinished()],
            orphans: [orphan(0, offset: 0), orphan(1, offset: 20), orphan(2, offset: 40)]
        )
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        await store.send(.recoverRequested(rid(0)))
        // 시트가 **먼저** 뜨고 숫자는 나중에 온다.
        #expect(store.state.recovering?.clipCount == nil)
        await store.receive(\.orphansCounted)
        #expect(store.state.recovering?.clipCount == 3)
        #expect(store.state.recovering?.canRecover == true)
    }

    /// 첫 프레임이 오기 전에 죽은 세션. 눌러도 할 일이 없다.
    @Test("영상이 없으면 복구할 수 없다")
    func 영상_없음() async {
        let (store, _, _) = makeStore([unfinished()], orphans: [])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        await store.send(.recoverRequested(rid(0)))
        await store.receive(\.orphansCounted)

        #expect(store.state.recovering?.clipCount == 0)
        #expect(store.state.recovering?.canRecover == false)
    }

    /// ⚠️ **이것이 없으면 "영상이 없습니다"와 "복구할 수 있습니다"가
    /// 동시에 뜬다.** 레코드의 클립이 0개라 `ClipAvailability`가
    /// `.missing`을 준다.
    @Test("미완 세션은 결손 확인을 건너뛴다")
    func 결손_제외() async {
        let (store, _, _) = makeStore([unfinished(id: rid(0)), finished(id: rid(1), dayOffset: -1)])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        #expect(store.state.availability[rid(0)] == nil)
        #expect(store.state.availability[rid(1)] != nil)
    }

    /// 정렬 키는 `startedAt`이다 — `endedAt`이 없다.
    @Test("미완 세션이 목록 맨 위에 온다")
    func 정렬() async {
        let (store, _, _) = makeStore([
            finished(id: rid(1), dayOffset: -1),
            unfinished(id: rid(0), dayOffset: 0),
            finished(id: rid(2), dayOffset: -2),
        ])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        guard case .loaded(let sessions) = store.state.phase else {
            Issue.record("목록이 없다"); return
        }
        #expect(sessions.map(\.id) == [rid(0), rid(1), rid(2)])
    }

    @Test("복구하면 클립이 붙고 세션이 닫힌다")
    func 복구() async {
        let repo = MutableRepository([unfinished()])
        let (store, _, _) = makeStore(
            [],
            orphans: [orphan(0, offset: 0), orphan(1, offset: 20)],
            repository: repo
        )
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)
        await store.send(.recoverRequested(rid(0)))
        await store.receive(\.orphansCounted)

        await store.send(.recoverConfirmed)
        await store.receive(\.recoverFinished)
        // 목록을 다시 읽는다 — 손으로 고치면 두 곳이 어긋난다.
        await store.receive(\.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        let saved = repo.sessions.first { $0.id == rid(0) }
        #expect(saved?.isUnfinished == false)
        #expect(saved?.recoveredAt == fixedNow)
        #expect(saved?.clips.count == 2)
        // 스윙 0개인데 **진단이 아니다.**
        #expect(saved?.swingCount == 0)
        #expect(saved?.needsDiagnosis == false)
        #expect(store.state.recovering == nil)
    }

    /// 시트를 띄운 뒤 파일이 사라졌다. 조용히 넘기면 복구된 줄 안다.
    @Test("복구할 영상이 없으면 실패를 알린다")
    func 복구_실패() async {
        let (store, _, _) = makeStore([unfinished()], orphans: [])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)
        await store.send(.recoverRequested(rid(0)))
        await store.receive(\.orphansCounted)

        await store.send(.recoverConfirmed)
        await store.receive(\.recoverFinished)

        #expect(store.state.deleteFailure?.contains("복구하지 못했습니다") == true)
    }

    @Test("폐기하면 고아 파일을 지우고 목록에서 뺀다")
    func 폐기() async {
        let log = RemovalLog()
        let repo = MutableRepository([unfinished(), finished(id: rid(1), dayOffset: -1)])
        let (store, _, _) = makeStore(
            [],
            orphans: [orphan(0, offset: 0), orphan(1, offset: 20)],
            log: log,
            repository: repo
        )
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)
        await store.send(.recoverRequested(rid(0)))
        await store.receive(\.orphansCounted)

        await store.send(.discardConfirmed)
        await store.receive(\.discardFinished)

        // 레코드에 없던 파일까지 지웠다.
        #expect(await log.removed == ["clip-0.mov", "clip-1.mov"])
        #expect(repo.sessions.map(\.id) == [rid(1)])
        guard case .loaded(let sessions) = store.state.phase else {
            Issue.record("목록이 없다"); return
        }
        #expect(sessions.map(\.id) == [rid(1)])
    }

    @Test("시트를 닫으면 아무 일도 일어나지 않는다")
    func 취소() async {
        let log = RemovalLog()
        let repo = MutableRepository([unfinished()])
        let (store, _, _) = makeStore([], log: log, repository: repo)
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)
        await store.send(.recoverRequested(rid(0)))
        await store.receive(\.orphansCounted)

        await store.send(.recoverDismissed)

        #expect(store.state.recovering == nil)
        #expect(await log.removed.isEmpty)
        #expect(repo.sessions.first?.isUnfinished == true)
    }

    /// 그 사이에 시트를 닫았으면 뒤늦은 스캔 결과를 버린다.
    @Test("닫힌 시트에는 숫자를 채우지 않는다")
    func 뒤늦은_스캔() async {
        let (store, _, _) = makeStore([unfinished()])
        await store.send(.appeared)
        await store.receive(\.loaded)
        await store.receive(\.availabilityChecked)

        await store.send(.orphansCounted(rid(0), 3))
        #expect(store.state.recovering == nil)
    }
}

@Suite("복구 시트 문구")
struct RecoverSheetTextTests {

    /// ⚠️ 확인 중에 "클립 0개"라고 쓰면 **거짓이다** — 아직 모른다.
    @Test("클립 수를 모르면 수를 적지 않는다")
    func 확인_중() {
        #expect(RecoverSheet.discardNotice(nil) == "되돌릴 수 없습니다")
    }

    /// #126의 결정 — "정말 지울까요?"만 묻는 것은 확인이 아니라 절차다.
    @Test("무엇이 사라지는지 숫자로 적는다")
    func 숫자() {
        #expect(RecoverSheet.discardNotice(3) == "클립 3개를 지웁니다 · 되돌릴 수 없습니다")
        #expect(RecoverSheet.discardNotice(0) == "클립 0개를 지웁니다 · 되돌릴 수 없습니다")
    }

    @Test("시각까지 적는다 — 같은 날 여러 번 찍는다")
    func 시각() {
        let text = LibraryFeature.whenText(start)
        #expect(text.contains("·"))
        #expect(text.contains(":"))
    }

    /// 레코드의 클립이 0개이므로 `subtitle`을 쓰면 "클립 0개"가 된다.
    @Test("미완 행의 둘째 줄에는 클립 수가 없다")
    func 둘째_줄() {
        let text = LibraryView.unfinishedSubtitle(unfinished())
        #expect(text == "볼머신 · 내 스윙 · 120fps")
        #expect(text.contains("클립") == false)
    }

    /// 아이콘도 색도 보이스오버에 읽히지 않는다.
    @Test("보이스오버가 미완 사실을 읽는다")
    func 보이스오버() {
        let label = LibraryView.rowLabel(unfinished(), nil)
        #expect(label.contains("지난 세션이 끝나지 않았습니다"))
        #expect(label.contains("스윙 수는 알 수 없습니다"))
        // 0개라고 읽으면 "못 찾았다"로 들린다.
        #expect(label.contains("스윙 0개") == false)
    }
}
