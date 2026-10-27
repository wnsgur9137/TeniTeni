import ComposableArchitecture
import Domain
import Foundation
import Synchronization
import Testing
@testable import Presentation

/// 정해진 답만 돌려주는 저장소. 실기기도 SwiftData도 필요 없다.
private final class StubRepository: SessionRepository, Sendable {
    enum Answer: Sendable {
        case found(Session)
        case missing
        case failure
    }

    struct Boom: LocalizedError {
        var errorDescription: String? { "디스크를 읽을 수 없습니다" }
    }

    private let answer: Answer
    private let loads = Mutex(0)

    init(_ answer: Answer) {
        self.answer = answer
    }

    var loadCount: Int { loads.withLock { $0 } }

    func save(_ session: Session) async throws {}
    func loadAll() async throws -> [Session] { [] }
    func delete(id: UUID) async throws {}

    func load(id: UUID) async throws -> Session? {
        loads.withLock { $0 += 1 }
        switch answer {
        case .found(let session): return session
        case .missing: return nil
        case .failure: throw Boom()
        }
    }
}

private func session(swings: Int, clips: Int = 1) -> Session {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let perClip = clips > 0 ? swings / clips : 0
    return Session(
        startedAt: start,
        endedAt: start.addingTimeInterval(124),
        situation: .ballMachine,
        observable: .swing,
        fps: 120,
        clips: (0..<clips).map { index in
            Clip(
                fileName: "clip-\(index).mov",
                recordedAt: start.addingTimeInterval(Double(index) * 10),
                fps: 120,
                swings: (0..<perClip).map { _ in
                    Swing(startSeconds: 0, endSeconds: 1, impactSeconds: 0.5)
                }
            )
        }
    )
}

@Suite("세션 요약")
@MainActor
struct SessionSummaryFeatureTests {

    @Test("세션을 읽어 요약으로 들어간다")
    func 읽기_성공() async {
        let stored = session(swings: 4, clips: 2)
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: stored.id)) {
            SessionSummaryFeature(repository: StubRepository(.found(stored)))
        }
        await store.send(.appeared)
        await store.receive(.loaded(stored)) { $0.phase = .loaded(stored) }
        #expect(store.state.isDiagnosis == false)
    }

    /// 빈 요약을 보여주면 사용자는 앱이 고장났다고 판단한다 — IA-FLOW.
    @Test("스윙 0개는 진단으로 갈린다")
    func 진단_분기() async {
        let empty = session(swings: 0, clips: 0)
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: empty.id)) {
            SessionSummaryFeature(repository: StubRepository(.found(empty)))
        }
        await store.send(.appeared)
        await store.receive(.loaded(empty)) { $0.phase = .loaded(empty) }
        #expect(store.state.isDiagnosis, "0개면 요약이 아니라 진단이다")
    }

    /// 클립은 있는데 스윙이 없는 경우도 진단이다 — 클립 수가 아니라 스윙 수로 센다.
    @Test("클립이 있어도 스윙이 0이면 진단이다")
    func 빈_클립() async {
        let empty = session(swings: 0, clips: 2)
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: empty.id)) {
            SessionSummaryFeature(repository: StubRepository(.found(empty)))
        }
        await store.send(.appeared)
        await store.receive(.loaded(empty)) { $0.phase = .loaded(empty) }
        #expect(store.state.isDiagnosis)
    }

    /// 조용히 빈 화면을 띄우면 사용자는 찍은 것이 사라졌다고 읽는다.
    @Test("읽기가 실패하면 사유를 남긴다")
    func 읽기_실패() async {
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: UUID())) {
            SessionSummaryFeature(repository: StubRepository(.failure))
        }
        await store.send(.appeared)
        await store.receive(.failed("디스크를 읽을 수 없습니다")) {
            $0.phase = .failed("기록을 읽지 못했습니다 — 디스크를 읽을 수 없습니다")
        }
        #expect(store.state.isDiagnosis == false, "실패는 진단이 아니다")
    }

    @Test("세션이 없으면 없다고 말한다")
    func 세션_없음() async {
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: UUID())) {
            SessionSummaryFeature(repository: StubRepository(.missing))
        }
        await store.send(.appeared)
        await store.receive(.missing) { $0.phase = .failed("이 세션의 기록이 없습니다") }
    }

    @Test("다시 시도하면 저장소를 한 번 더 읽는다")
    func 재시도() async {
        let stored = session(swings: 2)
        let repository = StubRepository(.found(stored))
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: stored.id)) {
            SessionSummaryFeature(repository: repository)
        }
        await store.send(.appeared)
        await store.receive(.loaded(stored)) { $0.phase = .loaded(stored) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(.loaded(stored)) { $0.phase = .loaded(stored) }
        #expect(repository.loadCount == 2)
    }

    @Test("닫기가 올라간다")
    func 닫기() async {
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: UUID())) {
            SessionSummaryFeature(repository: StubRepository(.missing))
        }
        await store.send(.closeTapped)
        await store.receive(.delegate(.closed))
    }

    /// 설정에서 추론하면 그 사이 사용자가 홈에서 다른 상황을 골랐을 때
    /// 엉뚱한 배치 안내를 보여준다. 그 세션이 찍던 상황을 들고 간다.
    @Test("배치 다시 보기는 그 세션의 상황을 들고 올라간다")
    func 배치_상황() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stored = Session(
            startedAt: start,
            endedAt: start.addingTimeInterval(30),
            situation: .wall,
            observable: .lineCall,
            fps: 60,
            clips: []
        )
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: stored.id)) {
            SessionSummaryFeature(repository: StubRepository(.found(stored)))
        }
        await store.send(.appeared)
        await store.receive(.loaded(stored)) { $0.phase = .loaded(stored) }
        await store.send(.reframeTapped)
        await store.receive(.delegate(.reframe(situation: .wall, observable: .lineCall)))
    }

    /// 읽지 못한 상태에서는 상황을 모른다. 보낼 것이 없으면 보내지 않는다.
    @Test("읽기 전에는 배치 다시 보기가 아무것도 보내지 않는다")
    func 배치_미로드() async {
        let store = TestStore(initialState: SessionSummaryFeature.State(sessionID: UUID())) {
            SessionSummaryFeature(repository: StubRepository(.missing))
        }
        await store.send(.reframeTapped)
    }

    @Test("소요 시간을 분·초로 적는다")
    func 소요_표기() {
        #expect(SessionSummaryView.duration(124) == "2분 4초")
        #expect(SessionSummaryView.duration(45) == "45초")
        #expect(SessionSummaryView.duration(60) == "1분 0초")
    }
}
