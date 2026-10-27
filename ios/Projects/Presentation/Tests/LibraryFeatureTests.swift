import ComposableArchitecture
import Domain
import Foundation
import Synchronization
import Testing
@testable import Presentation

/// 정해진 답만 돌려주는 저장소. 실기기도 SwiftData도 필요 없다.
private final class StubRepository: SessionRepository, Sendable {
    enum Answer: Sendable {
        case all([Session])
        case failure
    }

    struct Boom: LocalizedError {
        var errorDescription: String? { "디스크를 읽을 수 없습니다" }
    }

    private let answer: Answer
    private let loads = Mutex(0)

    init(_ answer: Answer) { self.answer = answer }

    var loadCount: Int { loads.withLock { $0 } }

    func save(_ session: Session) async throws {}
    func load(id: UUID) async throws -> Session? { nil }
    func delete(id: UUID) async throws {}

    func loadAll() async throws -> [Session] {
        loads.withLock { $0 += 1 }
        switch answer {
        case .all(let sessions): return sessions
        case .failure: throw Boom()
        }
    }
}

/// 기준 시각. 날짜 간격을 하루로 두면 정렬이 뒤집혀도 눈에 띈다.
private let base = Date(timeIntervalSince1970: 1_700_000_000)

private func session(dayOffset: Int, swings: Int = 1, clips: Int = 1) -> Session {
    let start = base.addingTimeInterval(Double(dayOffset) * 86_400)
    let perClip = clips > 0 ? swings / clips : 0
    return Session(
        startedAt: start,
        endedAt: start.addingTimeInterval(120),
        situation: .rally,
        observable: .swing,
        fps: 120,
        clips: (0..<clips).map { index in
            Clip(
                fileName: "clip-\(dayOffset)-\(index).mov",
                recordedAt: start,
                fps: 120,
                swings: (0..<perClip).map { _ in
                    Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5)
                }
            )
        }
    )
}

@Suite("보관함")
@MainActor
struct LibraryFeatureTests {

    @Test("세션을 읽어 목록으로 들어간다")
    func 읽기_성공() async {
        let stored = [session(dayOffset: 0), session(dayOffset: 1)]
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all(stored)))
        }
        await store.send(.appeared)
        await store.receive(.loaded(stored)) {
            // 1일이 0일보다 최신이므로 뒤집혀 들어간다.
            $0.phase = .loaded([stored[1], stored[0]])
        }
        #expect(store.state.isEmpty == false)
    }

    /// 저장소가 "최근 것부터"를 약속하지만 그 약속에 기대지 않는다.
    /// 순서가 바뀌는 날 화면은 **아무 오류도 내지 않고** 뒤섞인 목록을 보여준다.
    @Test("뒤섞여 와도 최신이 위로 간다")
    func 정렬() async {
        let old = session(dayOffset: 0)
        let mid = session(dayOffset: 5)
        let new = session(dayOffset: 9)
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all([mid, old, new])))
        }
        await store.send(.appeared)
        await store.receive(.loaded([mid, old, new])) {
            $0.phase = .loaded([new, mid, old])
        }
        guard case .loaded(let sessions) = store.state.phase else {
            Issue.record("목록이어야 한다")
            return
        }
        #expect(sessions.map(\.startedAt) == [new, mid, old].map(\.startedAt))
    }

    /// 빈 목록과 읽기 실패는 **다른 화면**이다. 레퍼런스 조사에서 반복된
    /// 불만은 "찾기 어렵다"가 아니라 "사라졌다"였다.
    @Test("아무것도 없으면 비어 있다고 말한다")
    func 빈_목록() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all([])))
        }
        await store.send(.appeared)
        await store.receive(.loaded([])) { $0.phase = .loaded([]) }
        #expect(store.state.isEmpty, "빈 목록은 빈 상태 화면으로 간다")
    }

    @Test("읽기가 실패하면 사유를 남기고, 비어 있다고 말하지 않는다")
    func 읽기_실패() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.failure))
        }
        await store.send(.appeared)
        await store.receive(.failed("디스크를 읽을 수 없습니다")) {
            $0.phase = .failed("기록을 읽지 못했습니다 — 디스크를 읽을 수 없습니다")
        }
        #expect(store.state.isEmpty == false, "실패는 '비어 있음'이 아니다")
    }

    @Test("다시 시도하면 저장소를 한 번 더 읽는다")
    func 재시도() async {
        let repository = StubRepository(.all([]))
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: repository)
        }
        await store.send(.appeared)
        await store.receive(.loaded([])) { $0.phase = .loaded([]) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(.loaded([])) { $0.phase = .loaded([]) }
        #expect(repository.loadCount == 2)
    }

    @Test("세션을 누르면 id가 올라간다")
    func 세션_탭() async {
        let stored = session(dayOffset: 0)
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all([stored])))
        }
        await store.send(.sessionTapped(stored.id))
        await store.receive(.delegate(.sessionTapped(stored.id)))
    }

    /// "없다"만 말하고 끝내면 사용자는 다음에 무엇을 할지 모른다.
    @Test("빈 상태의 촬영하러 가기가 올라간다")
    func 촬영_탭() async {
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all([])))
        }
        await store.send(.captureTapped)
        await store.receive(.delegate(.goToCapture))
    }

    /// 스윙 0개 세션도 목록에 남는다 — 영상은 있다(SPEC-0110).
    @Test("스윙 0개 세션도 목록에서 빠지지 않는다")
    func 스윙_0개도_남는다() async {
        let empty = session(dayOffset: 0, swings: 0, clips: 1)
        let store = TestStore(initialState: LibraryFeature.State()) {
            LibraryFeature(repository: StubRepository(.all([empty])))
        }
        await store.send(.appeared)
        await store.receive(.loaded([empty])) { $0.phase = .loaded([empty]) }
        #expect(store.state.isEmpty == false, "세션은 있다 — 그 안의 스윙이 0개일 뿐이다")
    }

    // MARK: 표기

    @Test("줄 부제는 상황·관찰 대상·클립 수·fps를 적는다")
    func 부제() {
        let stored = session(dayOffset: 0, swings: 4, clips: 2)
        #expect(LibraryView.subtitle(stored) == "랠리 · 내 스윙 · 클립 2개 · 120fps")
    }

    @Test("줄 날짜는 날짜와 시각을 함께 적는다")
    func 날짜() {
        // 1_700_000_000 = 2023-11-15 06:13:20 UTC. 표기는 기기 표준시를
        // 따르므로 시각 값 자체를 단정하지 않고 형식만 본다.
        let text = LibraryView.rowDate(base)
        #expect(text.contains("월"))
        #expect(text.contains("일 · "))
        #expect(text.count >= 10, "날짜만 적으면 같은 날 두 세션을 구분할 수 없다")
    }
}
