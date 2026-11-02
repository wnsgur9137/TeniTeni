import ComposableArchitecture
import Domain
import Foundation
import Testing
@testable import Presentation

private func mid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

private struct ListRepository: SessionRepository {
    let sessions: [Session]
    func save(_ session: Session) async throws {}
    func delete(id: UUID) async throws {}
    func loadAll() async throws -> [Session] { sessions }
    func load(id: UUID) async throws -> Session? { sessions.first { $0.id == id } }
}

/// 클립 2개 — 하나는 파일이 있고 하나는 없다. **일부 결손**을 볼 수 있는
/// 최소 구성.
private func twoClipSession(id: UUID = mid(0)) -> Session {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return Session(
        id: id,
        startedAt: start,
        situation: .ballMachine,
        fps: 120,
        clips: [
            Clip(
                id: mid(10),
                fileName: "a.mov",
                recordedAt: start,
                fps: 120,
                swings: [Swing(id: mid(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2)]
            ),
            Clip(
                id: mid(11),
                fileName: "gone.mov",
                recordedAt: start.addingTimeInterval(20),
                fps: 120,
                swings: [Swing(id: mid(2), startSeconds: 2, endSeconds: 4, impactSeconds: 3)]
            ),
        ]
    )
}

private func makeLocator(present: Set<String>) -> ClipLocator {
    ClipLocator(directory: URL(filePath: "/clips")) { present.contains($0.lastPathComponent) }
}

@Suite("보관함 — 클립 결손")
@MainActor
struct LibraryMissingClipTests {

    /// **목록이 먼저 그려지고 결손 표시가 나중에 붙는다.** 읽기가 느려도
    /// 목록이 뜨는 것 자체가 늦어지지 않는다.
    @Test("목록을 읽은 뒤 결손을 확인한다")
    func 확인_순서() async {
        let session = twoClipSession()
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }

        await store.send(.appeared)
        await store.receive(.loaded([session])) {
            $0.phase = .loaded([session])
        }
        // 목록이 그려진 **뒤에** 온다.
        await store.receive(.availabilityChecked([session.id: .partial])) {
            $0.availability = [session.id: .partial]
        }
    }

    @Test("전부 없으면 none, 전부 있으면 all")
    func 단계() async {
        let session = twoClipSession()

        for (present, expected) in [
            (Set<String>(), ClipAvailability.missing),
            (Set(["a.mov", "gone.mov"]), ClipAvailability.all),
        ] {
            let store = TestStore(initialState: LibraryFeature.State()) {
                LibraryFeature(
                    repository: ListRepository(sessions: [session]),
                    locator: makeLocator(present: present)
                )
            }
            store.exhaustivity = .off
            await store.send(.appeared)
            await store.receive(.loaded([session]))
            await store.receive(.availabilityChecked([session.id: expected]))
            #expect(store.state.availability[session.id] == expected)
        }
    }

    /// 그 사이에 파일이 지워졌을 수 있고, **그것이 이 확인의 존재 이유다.**
    @Test("다시 읽으면 지난 확인을 버린다")
    func 캐시_안_함() async {
        let session = twoClipSession()
        let store = TestStore(
            initialState: LibraryFeature.State(
                phase: .loaded([session]),
                availability: [session.id: .all]
            )
        ) {
            LibraryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }
        store.exhaustivity = .off

        await store.send(.appeared) {
            $0.phase = .loading
            // 지난 값을 들고 있으면 새 목록에 옛 판정이 붙는다.
            $0.availability = [:]
        }
        await store.receive(.loaded([session]))
        await store.receive(.availabilityChecked([session.id: .partial]))
        #expect(store.state.availability[session.id] == .partial)
    }

    /// 지난 확인 결과를 새 목록에 붙이면 **엉뚱한 세션에 경고가 붙는다.**
    @Test("목록에 없는 세션의 확인 결과는 버린다")
    func 어긋난_결과() async {
        let session = twoClipSession()
        let store = TestStore(initialState: LibraryFeature.State(phase: .loaded([session]))) {
            LibraryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: [])
            )
        }
        await store.send(
            .availabilityChecked([session.id: .missing, mid(999): .partial])
        ) {
            $0.availability = [session.id: .missing]
        }
    }

    @Test("목록을 읽기 전에 온 결과는 버린다")
    func 로딩_중_결과() async {
        let store = TestStore(initialState: LibraryFeature.State(phase: .loading)) {
            LibraryFeature(
                repository: ListRepository(sessions: []),
                locator: makeLocator(present: [])
            )
        }
        await store.send(.availabilityChecked([mid(0): .missing]))
        #expect(store.state.availability.isEmpty)
    }

    /// ⚠️ **`none`이라는 이름의 함정을 고정한다.** 이 타입이 옵셔널로
    /// 들리므로 `.none`은 `Optional.none`으로 해석된다 — 컴파일은 통과하고
    /// 조용히 `nil`이 된다. 처음에 그렇게 써서 이 테스트가 잡아냈다.
    @Test("결손 상태와 미확인(nil)이 구분된다")
    func 결손과_미확인() {
        let session = twoClipSession()
        // 미확인은 평소 부제목, 결손은 경고.
        #expect(LibraryView.rowLabel(session, nil).contains("클립 2개"))
        #expect(LibraryView.rowLabel(session, .missing).contains("영상이 없습니다"))
        #expect(LibraryView.rowLabel(session, nil) != LibraryView.rowLabel(session, .missing))
    }

    /// **수를 바꾸지 않는다.** 찍은 사실은 지워지지 않았다.
    @Test("결손이 있어도 스윙 수는 그대로다")
    func 수_유지() {
        let session = twoClipSession()
        #expect(session.swingCount == 2)
        // 날짜 문자열은 시간대에 따라 달라지므로 단정하지 않는다.
        for availability in [ClipAvailability.missing, .partial, .all, nil] {
            let label = LibraryView.rowLabel(session, availability)
            // **수는 어느 경우에도 그대로다.**
            #expect(label.hasSuffix("스윙 2개"))
        }
        #expect(LibraryView.rowLabel(session, .missing).contains("영상이 없습니다"))
        #expect(LibraryView.rowLabel(session, .partial).contains("영상 일부 없음"))
        // 전부 있으면 평소 부제목이 온다.
        #expect(LibraryView.rowLabel(session, .all).contains("클립 2개"))
        #expect(LibraryView.rowLabel(session, nil).contains("클립 2개"))
        // 결손 문구가 부제목을 **대신한다** — 둘이 같이 나오면 행 높이가
        // 세션마다 달라진다.
        #expect(!LibraryView.rowLabel(session, .missing).contains("클립 2개"))
    }
}

@Suite("요약 — 클립 결손")
@MainActor
struct SummaryMissingClipTests {

    @Test("세션을 읽은 뒤 결손 클립을 확인한다")
    func 확인_순서() async {
        let session = twoClipSession()
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: session.id)) {
            SessionSummaryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }

        await store.send(.appeared)
        await store.receive(.loaded(session)) { $0.phase = .loaded(session) }
        await store.receive(.missingClipsChecked([mid(11)])) {
            $0.missingClips = [mid(11)]
        }
    }

    /// 열면 `ReplayMissing`이 뜨는데, **열리기 전에 알 수 있으면** 화면
    /// 전환과 방향 잠금을 치를 이유가 없다.
    @Test("영상이 없는 클립의 스윙은 리플레이를 열지 않는다")
    func 탭_차단() async {
        let session = twoClipSession()
        let store = TestStore(
            initialState: SessionSummaryFeature.State(
                sessionID: session.id,
                phase: .loaded(session),
                missingClips: [mid(11)]
            )
        ) {
            SessionSummaryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }

        // 없는 클립의 스윙 — 아무 일도 없다.
        await store.send(.swingTapped(mid(2)))
        // 있는 클립의 스윙 — 열린다.
        await store.send(.swingTapped(mid(1)))
        await store.receive(
            .delegate(.openReplay(sessionID: session.id, swingID: mid(1)))
        )
    }

    /// 확인 전에는 경고가 없다. **거짓을 말하는 시간이 짧아지는 것이
    /// 목적이고 0이 되는 것은 아니다.**
    @Test("확인 전에는 열린다")
    func 확인_전() async {
        let session = twoClipSession()
        let store = TestStore(
            initialState: SessionSummaryFeature.State(
                sessionID: session.id,
                phase: .loaded(session)
            )
        ) {
            SessionSummaryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }
        await store.send(.swingTapped(mid(2)))
        await store.receive(
            .delegate(.openReplay(sessionID: session.id, swingID: mid(2)))
        )
    }

    @Test("세션에 없는 클립의 확인 결과는 버린다")
    func 어긋난_결과() async {
        let session = twoClipSession()
        let store = TestStore(
            initialState: SessionSummaryFeature.State(
                sessionID: session.id,
                phase: .loaded(session)
            )
        ) {
            SessionSummaryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: [])
            )
        }
        await store.send(.missingClipsChecked([mid(10), mid(999)])) {
            $0.missingClips = [mid(10)]
        }
    }

    @Test("다시 읽으면 지난 확인을 버린다")
    func 캐시_안_함() async {
        let session = twoClipSession()
        let store = TestStore(
            initialState: SessionSummaryFeature.State(
                sessionID: session.id,
                phase: .loaded(session),
                missingClips: [mid(10), mid(11)]
            )
        ) {
            SessionSummaryFeature(
                repository: ListRepository(sessions: [session]),
                locator: makeLocator(present: ["a.mov"])
            )
        }
        store.exhaustivity = .off

        await store.send(.retryTapped) {
            $0.phase = .loading
            $0.missingClips = []
        }
        await store.receive(.loaded(session))
        await store.receive(.missingClipsChecked([mid(11)]))
        #expect(store.state.missingClips == [mid(11)])
    }
}
