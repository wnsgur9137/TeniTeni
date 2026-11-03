import ComposableArchitecture
import Domain
import Foundation
import Synchronization
import Testing
import TeniVision
@testable import Presentation

private func fid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

/// 지운 파일 이름을 기록한다. **사이드카까지 지우는지**가 여기서 드러난다.
private actor RemovalLog {
    private(set) var removed: [String] = []
    func add(_ name: String) { removed.append(name) }
}

private struct SpyFiles: ClipFileStore {
    let log: RemovalLog
    func remove(fileName: String) async { await log.add(fileName) }
}

/// `NSLock`을 비동기 맥락에서 잡으면 Swift 6가 막는다 — 스레드가
/// 바뀔 수 있으므로 `unlock`이 다른 스레드에서 돌 수 있다.
/// `Mutex`는 범위로 잡으므로 안전하다.
private final class MutableRepository: SessionRepository, Sendable {
    private let stored: Mutex<[Session]>
    let failsDelete: Bool

    struct Boom: LocalizedError {
        var errorDescription: String? { "디스크를 쓸 수 없습니다" }
    }

    init(_ initial: [Session], failsDelete: Bool = false) {
        self.stored = Mutex(initial)
        self.failsDelete = failsDelete
    }

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
        if failsDelete { throw Boom() }
        stored.withLock { $0.removeAll { $0.id == id } }
    }
}

private func twoClipSession(id: UUID = fid(0)) -> Session {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return Session(
        id: id,
        startedAt: start,
        situation: .wall,
        fps: 120,
        clips: [
            Clip(
                id: fid(10), fileName: "a.mov", recordedAt: start, fps: 120,
                swings: [
                    Swing(id: fid(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2),
                    Swing(id: fid(2), startSeconds: 5, endSeconds: 7, impactSeconds: 6),
                ]
            ),
            Clip(
                id: fid(11), fileName: "b.mov",
                recordedAt: start.addingTimeInterval(20), fps: 120,
                swings: [Swing(id: fid(3), startSeconds: 2, endSeconds: 4, impactSeconds: 3)]
            ),
        ]
    )
}

private func anyLocator() -> ClipLocator {
    ClipLocator(directory: URL(filePath: "/clips")) { _ in true }
}

/// 되돌리기가 없으므로(SPEC-0126 선택지 3) **확인 문구가 유일한
/// 안전장치다.** 문구가 틀리면 사용자가 다른 것을 지운다.
@Suite("삭제 확인 문구")
struct DeleteTargetTests {

    @Test("세션은 날짜·상황과 사라지는 수를 적는다")
    func 세션_문구() {
        let target = DeleteTarget.session(twoClipSession(), dateText: "11월 1일")
        #expect(target.title == "이 세션을 지울까요?")
        #expect(target.detail == "11월 1일 · 벽치기")
        #expect(target.counts == "스윙 3개 · 클립 2개")
        #expect(target.warning == "영상을 함께 지우고, 되돌릴 수 없습니다.")
        #expect(target.isLastClip == false)
        #expect(target.sessionID == fid(0))
    }

    @Test("클립은 그 클립의 스윙 수를 적는다")
    func 클립_문구() {
        let session = twoClipSession()
        let target = DeleteTarget.clip(session.clips[0], in: session, dateText: "11월 1일")
        #expect(target.title == "이 클립을 지울까요?")
        #expect(target.counts == "스윙 2개 · 클립 1개")
        #expect(target.isLastClip == false)
    }

    /// ⚠️ **세션이 사라지는 것을 모르고 지우면 그것이 가장 나쁜 실수다.**
    @Test("마지막 클립은 제목과 경고가 다르다")
    func 마지막_클립_문구() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: fid(0), startedAt: start, situation: .wall, fps: 120,
            clips: [
                Clip(
                    id: fid(10), fileName: "a.mov", recordedAt: start, fps: 120,
                    swings: [Swing(id: fid(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2)]
                )
            ]
        )
        let target = DeleteTarget.clip(session.clips[0], in: session, dateText: "11월 1일")
        #expect(target.title == "마지막 클립입니다")
        #expect(target.warning == "세션도 함께 지워집니다. 되돌릴 수 없습니다.")
        #expect(target.isLastClip)
        // 일반 클립과 **다른 문구**여야 한다.
        #expect(target.warning != DeleteTarget.session(session, dateText: "11월 1일").warning)
    }

    /// 스윙 0개 세션도 영상은 있고, 지우면 그 영상이 사라진다.
    @Test("0개도 숫자로 적는다")
    func 영개() {
        #expect(DeleteTarget.counts(swings: 0, clips: 1) == "스윙 0개 · 클립 1개")
    }
}

@Suite("보관함 — 삭제")
@MainActor
struct LibraryDeleteTests {

    private func makeStore(
        _ repository: MutableRepository,
        log: RemovalLog
    ) -> TestStoreOf<LibraryFeature> {
        TestStore(
            initialState: LibraryFeature.State(phase: .loaded(repository.sessions))
        ) {
            LibraryFeature(
                repository: repository,
                locator: anyLocator(),
                files: SpyFiles(log: log)
            )
        }
    }

    /// **아직 지우지 않는다.** 지울 것을 적어서 보여주고 묻는다.
    @Test("스와이프 삭제는 확인을 먼저 띄운다")
    func 확인_먼저() async {
        let session = twoClipSession()
        let log = RemovalLog()
        let store = makeStore(MutableRepository([session]), log: log)

        await store.send(.deleteRequested(session.id)) {
            $0.deleting = .session(
                session, dateText: LibraryFeature.dateText(session.startedAt)
            )
        }
        // 파일은 아직 그대로다.
        #expect(await log.removed.isEmpty)
    }

    @Test("취소하면 아무것도 지우지 않는다")
    func 취소() async {
        let session = twoClipSession()
        let log = RemovalLog()
        let store = makeStore(MutableRepository([session]), log: log)

        await store.send(.deleteRequested(session.id)) {
            $0.deleting = .session(
                session, dateText: LibraryFeature.dateText(session.startedAt)
            )
        }
        await store.send(.deleteCancelled) { $0.deleting = nil }
        #expect(await log.removed.isEmpty)
    }

    @Test("확인하면 파일 전부와 레코드를 지우고 목록에서 뺀다")
    func 삭제() async {
        let session = twoClipSession()
        let repository = MutableRepository([session])
        let log = RemovalLog()
        let store = makeStore(repository, log: log)

        await store.send(.deleteRequested(session.id)) {
            $0.deleting = .session(
                session, dateText: LibraryFeature.dateText(session.startedAt)
            )
        }
        await store.send(.deleteConfirmed) { $0.deleting = nil }
        await store.receive(.deleteFinished(.success(session.id))) {
            // 다시 읽기 전에도 목록에서 뺀다 — 남아 있으면 **지워지지
            // 않은 것처럼 보인다.**
            $0.phase = .loaded([])
        }
        #expect(await log.removed == ["a.mov", "b.mov"])
        #expect(repository.sessions.isEmpty)
    }

    /// 조용히 넘기면 사용자는 지워진 줄 안다 — 실제로는 **영상만 사라지고
    /// 레코드가 남았다.**
    @Test("레코드 삭제가 실패하면 사유를 보여준다")
    func 실패_고지() async {
        let session = twoClipSession()
        let repository = MutableRepository([session], failsDelete: true)
        let log = RemovalLog()
        let store = makeStore(repository, log: log)
        store.exhaustivity = .off

        await store.send(.deleteRequested(session.id))
        await store.send(.deleteConfirmed)
        await store.receive(\.deleteFinished)
        #expect(store.state.deleteFailure?.hasPrefix("지우지 못했습니다") == true)
        // 목록에서 빠지지 않는다 — 레코드가 남아 있다.
        #expect(store.state.phase == .loaded([session]))
        // 그래도 **파일은 지워졌다.** 되돌리지 않는다.
        #expect(await log.removed == ["a.mov", "b.mov"])
    }

    /// 확인을 띄운 뒤 목록이 바뀔 수 있다. **들고 있던 값이 아니라 다시
    /// 찾는다** — 그 사이에 바뀐 것을 지우면 안 된다.
    @Test("확인 뒤 목록에서 사라진 세션은 지우지 않는다")
    func 사라진_세션() async {
        let session = twoClipSession()
        let log = RemovalLog()
        let store = makeStore(MutableRepository([session]), log: log)

        await store.send(.deleteRequested(session.id)) {
            $0.deleting = .session(
                session, dateText: LibraryFeature.dateText(session.startedAt)
            )
        }
        // 그 사이에 목록이 비었다.
        await store.send(.loaded([])) { $0.phase = .loaded([]) }
        await store.receive(.availabilityChecked([:]))
        await store.send(.deleteConfirmed) { $0.deleting = nil }
        #expect(await log.removed.isEmpty)
    }

    @Test("목록에 없는 세션은 확인도 띄우지 않는다")
    func 없는_세션() async {
        let log = RemovalLog()
        let store = makeStore(MutableRepository([]), log: log)
        await store.send(.deleteRequested(fid(999)))
    }
}

@Suite("리플레이 — 클립 삭제")
@MainActor
struct ReplayDeleteTests {

    private func makeStore(
        _ repository: MutableRepository,
        log: RemovalLog,
        session: Session
    ) -> TestStoreOf<ReplayFeature> {
        TestStore(
            initialState: ReplayFeature.State(
                sessionID: session.id,
                swingID: fid(1),
                phase: .ready(items: ReplayItem.playlist(from: session), index: 0),
                clipURL: URL(filePath: "/clips/a.mov"),
                session: session
            )
        ) {
            ReplayFeature(
                repository: repository,
                locator: anyLocator(),
                files: SpyFiles(log: log)
            )
        }
    }

    @Test("메뉴에서 삭제를 누르면 확인을 띄우고 재생을 멈춘다")
    func 확인_먼저() async {
        let session = twoClipSession()
        let log = RemovalLog()
        let store = makeStore(MutableRepository([session]), log: log, session: session)

        await store.send(.playPauseTapped) { $0.isPlaying = true }
        await store.send(.deleteRequested) {
            // 다이얼로그 뒤에서 영상이 돌면 무엇을 지우는지 보려고
            // 사용자가 다이얼로그를 닫는다.
            $0.isPlaying = false
            $0.deleting = .clip(
                session.clips[0], in: session,
                dateText: ReplayFeature.dateText(session.startedAt)
            )
        }
        #expect(await log.removed.isEmpty)
    }

    /// ★ **닫는다.** 다음 클립으로 넘기면 "34개 중 12번째"의 분모가 화면
    /// 안에서 바뀐다.
    @Test("지우면 리플레이를 닫는다")
    func 닫힌다() async {
        let session = twoClipSession()
        let repository = MutableRepository([session])
        let log = RemovalLog()
        let store = makeStore(repository, log: log, session: session)
        store.exhaustivity = .off

        await store.send(.deleteRequested)
        await store.send(.deleteConfirmed)
        await store.receive(\.deleteFinished)
        await store.receive(.delegate(.deleted))
        #expect(store.state.isPlaying == false)
        #expect(store.state.isFullscreen == false)
        #expect(await log.removed == ["a.mov"])
        // 클립 하나만 지웠으므로 세션은 남고 클립이 하나다.
        #expect(repository.sessions.first?.clips.count == 1)
    }

    @Test("마지막 클립을 지우면 세션도 사라진다")
    func 마지막_클립() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(
            id: fid(0), startedAt: start, situation: .wall, fps: 120,
            clips: [
                Clip(
                    id: fid(10), fileName: "a.mov", recordedAt: start, fps: 120,
                    swings: [Swing(id: fid(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2)]
                )
            ]
        )
        let repository = MutableRepository([session])
        let log = RemovalLog()
        let store = makeStore(repository, log: log, session: session)
        store.exhaustivity = .off

        await store.send(.deleteRequested)
        #expect(store.state.deleting?.isLastClip == true)
        await store.send(.deleteConfirmed)
        await store.receive(\.deleteFinished)
        await store.receive(.delegate(.deleted))
        #expect(repository.sessions.isEmpty)
    }

    @Test("취소하면 아무것도 지우지 않는다")
    func 취소() async {
        let session = twoClipSession()
        let log = RemovalLog()
        let store = makeStore(MutableRepository([session]), log: log, session: session)

        await store.send(.deleteRequested) {
            $0.isPlaying = false
            $0.deleting = .clip(
                session.clips[0], in: session,
                dateText: ReplayFeature.dateText(session.startedAt)
            )
        }
        await store.send(.deleteCancelled) { $0.deleting = nil }
        #expect(await log.removed.isEmpty)
    }

    @Test("세션을 읽기 전에는 삭제를 띄우지 않는다")
    func 세션_없음() async {
        let log = RemovalLog()
        let store = TestStore(
            initialState: ReplayFeature.State(sessionID: fid(0), swingID: fid(1))
        ) {
            ReplayFeature(
                repository: MutableRepository([]),
                locator: anyLocator(),
                files: SpyFiles(log: log)
            )
        }
        await store.send(.deleteRequested)
        #expect(store.state.deleting == nil)
    }
}
