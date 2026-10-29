import ComposableArchitecture
import Domain
import Foundation
import Testing
@testable import Presentation

/// 정해진 세션만 돌려주는 저장소.
private struct StubRepository: SessionRepository {
    enum Answer: Sendable {
        case found(Session)
        case missing
        case failure
    }

    struct Boom: LocalizedError {
        var errorDescription: String? { "디스크를 읽을 수 없습니다" }
    }

    let answer: Answer

    func save(_ session: Session) async throws {}
    func loadAll() async throws -> [Session] { [] }
    func delete(id: UUID) async throws {}

    func load(id: UUID) async throws -> Session? {
        switch answer {
        case .found(let session): return session
        case .missing: return nil
        case .failure: throw Boom()
        }
    }
}

/// 결정적 UUID. 기대값을 손으로 적을 수 있게 한다.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

@Suite("리플레이")
@MainActor
struct ReplayFeatureTests {

    // MARK: 픽스처

    /// 클립 2개, 스윙 3개. **클립 경계를 넘는 넘기기**를 볼 수 있는 최소 구성.
    private struct Fixture {
        let session: Session
        let items: [ReplayItem]

        init(secondClipFPS: Int = 60) {
            let start = Date(timeIntervalSince1970: 1_700_000_000)
            let session = Session(
                id: id(0),
                startedAt: start,
                situation: .ballMachine,
                fps: 120,
                clips: [
                    Clip(
                        id: id(10),
                        fileName: "a.mov",
                        recordedAt: start,
                        fps: 120,
                        swings: [
                            Swing(id: id(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2),
                            Swing(id: id(2), startSeconds: 5, endSeconds: 7, impactSeconds: 6),
                        ]
                    ),
                    Clip(
                        id: id(11),
                        fileName: "b.mov",
                        recordedAt: start.addingTimeInterval(20),
                        fps: secondClipFPS,
                        swings: [
                            Swing(id: id(3), startSeconds: 2, endSeconds: 4, impactSeconds: 2.5)
                        ]
                    ),
                ]
            )
            self.session = session
            self.items = ReplayItem.playlist(from: session)
        }
    }

    private func makeStore(
        _ fixture: Fixture = Fixture(),
        swingID: UUID,
        present: Set<String> = ["a.mov", "b.mov"]
    ) -> TestStoreOf<ReplayFeature> {
        let root = URL(filePath: "/clips")
        return TestStore(
            initialState: ReplayFeature.State(sessionID: id(0), swingID: swingID)
        ) {
            ReplayFeature(
                repository: StubRepository(answer: .found(fixture.session)),
                locator: ClipLocator(directory: root) { present.contains($0.lastPathComponent) }
            )
        }
    }

    // MARK: 열기

    @Test("지정된 스윙으로 열리고 구간 시작으로 간다")
    func 열기() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(2))

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.loaded(fixture.session)) {
            $0.phase = .ready(items: fixture.items, index: 1)
            $0.clipURL = URL(filePath: "/clips/a.mov")
            // **임팩트가 아니라 구간 시작.** 지표가 없는 동안에는 스윙을
            // 처음부터 본다(SPEC-0123 선택지 4).
            $0.currentSeconds = 5
            $0.seek = .init(tick: 1, seconds: 5)
            $0.isPlaying = true
        }
        #expect(store.state.current?.position == 2)
        #expect(store.state.speed == .quarter)
    }

    @Test("기본 배속은 0.25×다")
    func 기본_배속() {
        let state = ReplayFeature.State(sessionID: id(0), swingID: id(1))

        #expect(state.speed == .quarter)
        #expect(state.effectiveSpeed == .quarter)
    }

    @Test("목록에 없는 스윙으로 열면 첫 칸으로 떨어진다")
    func 없는_스윙() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(999))

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.loaded(fixture.session)) {
            $0.phase = .ready(items: fixture.items, index: 0)
            $0.clipURL = URL(filePath: "/clips/a.mov")
            $0.currentSeconds = 1
            $0.seek = .init(tick: 1, seconds: 1)
            $0.isPlaying = true
        }
    }

    // MARK: 넘기기

    @Test("클립 경계를 넘어 다음 스윙으로 간다")
    func 클립_경계_넘기기() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(2))
        await open(store, fixture, index: 1, url: "a.mov", start: 5)

        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 2)
            // 클립이 바뀌었으므로 파일을 다시 찾는다.
            $0.clipURL = URL(filePath: "/clips/b.mov")
            $0.currentSeconds = 2
            $0.seek = .init(tick: 2, seconds: 2)
        }
        #expect(store.state.current?.fileName == "b.mov")
        #expect(store.state.current?.clipFPS == 60)
        #expect(store.state.canGoNext == false)
    }

    @Test("같은 클립 안에서는 seek만 하고 파일을 다시 찾지 않는다")
    func 같은_클립() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 1)
            $0.currentSeconds = 5
            $0.seek = .init(tick: 2, seconds: 5)
        }
        // `clipURL`이 그대로다 — 아이템을 갈지 않으므로 재생이 끊기지 않는다.
        #expect(store.state.clipURL == URL(filePath: "/clips/a.mov"))
    }

    @Test("같은 클립 안에서는 느린 재생 가능 여부를 다시 묻지 않는다")
    func 같은_클립_슬로우모션_유지() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.slowMotionUnsupported(true)) {
            $0.slowMotionUnsupported = true
            $0.speed = .normal
        }
        // 같은 아이템이므로 플레이어가 **다시 보고하지 않는다.** 칸이 바뀔
        // 때마다 초기화하면 이 사실이 지워지고 배속 칩이 되살아난다.
        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 1)
            $0.currentSeconds = 5
            $0.seek = .init(tick: 2, seconds: 5)
        }
        #expect(store.state.slowMotionUnsupported)

        // 클립이 바뀌면 다시 묻는다 — 새 아이템은 성질이 다를 수 있다.
        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 2)
            $0.clipURL = URL(filePath: "/clips/b.mov")
            $0.slowMotionUnsupported = false
            $0.currentSeconds = 2
            $0.seek = .init(tick: 3, seconds: 2)
        }
    }

    @Test("첫 칸에서 뒤로, 마지막 칸에서 앞으로는 막힌다")
    func 경계() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        #expect(store.state.canGoPrevious == false)
        await store.send(.previousTapped)

        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 1)
            $0.currentSeconds = 5
            $0.seek = .init(tick: 2, seconds: 5)
        }
        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 2)
            $0.clipURL = URL(filePath: "/clips/b.mov")
            $0.currentSeconds = 2
            $0.seek = .init(tick: 3, seconds: 2)
        }
        #expect(store.state.canGoNext == false)
        await store.send(.nextTapped)
    }

    // MARK: 배속

    @Test("배속을 고르면 바뀐다")
    func 배속_전환() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.speedSelected(.eighth)) { $0.speed = .eighth }
        #expect(store.state.effectiveSpeed == .eighth)
        await store.send(.speedSelected(.normal)) { $0.speed = .normal }
    }

    @Test("느린 재생을 못 하는 클립에서는 1×로 고정된다")
    func 슬로우모션_불가() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.slowMotionUnsupported(true)) {
            $0.slowMotionUnsupported = true
            $0.speed = .normal
        }
        // 칩을 눌러도 바뀌지 않는다. 바뀐 것처럼 보이고 1×로 재생하면
        // 사용자가 "느리게 안 된다"를 영상으로 오해한다.
        await store.send(.speedSelected(.quarter))
        #expect(store.state.effectiveSpeed == .normal)
    }

    // MARK: 임팩트 · 프레임 · 반복

    @Test("임팩트를 누르면 그 시각으로 가고 재생이 멈춘다")
    func 임팩트_점프() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(2))
        await open(store, fixture, index: 1, url: "a.mov", start: 5)

        await store.send(.impactTapped) {
            $0.isPlaying = false
            $0.currentSeconds = 6
            $0.seek = .init(tick: 2, seconds: 6)
        }
    }

    @Test("프레임 이동은 먼저 멈추고 스텝을 올린다")
    func 프레임_이동() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.stepTapped(1)) {
            // 재생과 스텝이 섞이면 어디로 갔는지 알 수 없다.
            $0.isPlaying = false
            $0.step = .init(tick: 1, count: 1)
        }
        await store.send(.stepTapped(-1)) {
            $0.step = .init(tick: 2, count: -1)
        }
        // 0 스텝은 명령을 만들지 않는다.
        await store.send(.stepTapped(0))
    }

    @Test("구간 끝에 닿으면 시작으로 되감는다")
    func 구간_반복() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.timeObserved(2.9)) { $0.currentSeconds = 2.9 }
        await store.send(.reachedEnd) {
            $0.currentSeconds = 1
            $0.seek = .init(tick: 2, seconds: 1)
        }
        // 재생은 계속된다 — 멈추면 1~2초마다 다시 눌러야 한다.
        #expect(store.state.isPlaying)
    }

    @Test("스크러버를 끌면 그 비율의 시각으로 간다")
    func 스크럽() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        // 구간은 1~3초. 0.5 → 2초.
        await store.send(.scrubbed(0.5)) {
            $0.currentSeconds = 2
            $0.seek = .init(tick: 2, seconds: 2)
        }
        // 범위 밖은 조인다.
        await store.send(.scrubbed(2)) {
            $0.currentSeconds = 3
            $0.seek = .init(tick: 3, seconds: 3)
        }
    }

    // MARK: 파일 없음

    @Test("클립 파일이 없으면 재생을 막고 넘기기는 살린다")
    func 파일_없음() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(3), present: ["a.mov"])

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.loaded(fixture.session)) {
            $0.phase = .ready(items: fixture.items, index: 2)
            $0.clipURL = nil
            $0.currentSeconds = 2
            $0.seek = .init(tick: 1, seconds: 2)
        }
        #expect(store.state.isClipMissing)
        // **열려도 재생하지 않는다.**
        #expect(store.state.isPlaying == false)

        await store.send(.playPauseTapped)
        await store.send(.impactTapped)
        await store.send(.stepTapped(1))

        // 넘기기는 살아 있다 — 건너뛰면 "3개 중 3번째"의 분모가 달라진다.
        #expect(store.state.canGoPrevious)
        await store.send(.previousTapped) {
            $0.phase = .ready(items: fixture.items, index: 1)
            $0.clipURL = URL(filePath: "/clips/a.mov")
            $0.currentSeconds = 5
            $0.seek = .init(tick: 2, seconds: 5)
        }
        #expect(store.state.isClipMissing == false)
    }

    @Test("있는 칸에서 없는 칸으로 넘어가면 재생이 멈춘다")
    func 없는_칸으로() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(2), present: ["a.mov"])
        await open(store, fixture, index: 1, url: "a.mov", start: 5)
        #expect(store.state.isPlaying)

        await store.send(.nextTapped) {
            $0.phase = .ready(items: fixture.items, index: 2)
            $0.clipURL = nil
            $0.currentSeconds = 2
            $0.seek = .init(tick: 2, seconds: 2)
            $0.isPlaying = false
        }
    }

    // MARK: 전체화면 · 실패

    @Test("전체화면을 켜고 끈다. 닫으면 반드시 꺼진다")
    func 전체화면() async {
        let fixture = Fixture()
        let store = makeStore(fixture, swingID: id(1))
        await open(store, fixture, index: 0, url: "a.mov", start: 1)

        await store.send(.fullscreenToggled) { $0.isFullscreen = true }
        await store.send(.closeTapped) {
            // 가로 잠금을 푸는 쪽이 이 상태를 보고 있다. 켜진 채로 닫으면
            // 요약과 보관함이 가로로 남는다.
            $0.isFullscreen = false
            $0.isPlaying = false
        }
        await store.receive(.delegate(.closed))
    }

    @Test("스윙이 0개인 세션은 실패로 떨어진다")
    func 스윙_0개() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let empty = Session(
            id: id(0),
            startedAt: start,
            situation: .ballMachine,
            fps: 120,
            clips: [Clip(fileName: "a.mov", recordedAt: start, fps: 120, swings: [])]
        )
        let store = TestStore(
            initialState: ReplayFeature.State(sessionID: id(0), swingID: id(1))
        ) {
            ReplayFeature(
                repository: StubRepository(answer: .found(empty)),
                locator: ClipLocator(directory: URL(filePath: "/clips")) { _ in true }
            )
        }

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.loaded(empty)) {
            $0.phase = .failed("이 세션에는 스윙이 없습니다")
        }
    }

    @Test("세션이 없으면 사유를 적는다")
    func 세션_없음() async {
        let store = TestStore(
            initialState: ReplayFeature.State(sessionID: id(0), swingID: id(1))
        ) {
            ReplayFeature(repository: StubRepository(answer: .missing))
        }

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.missing) {
            $0.phase = .failed("이 세션의 기록이 없습니다")
        }
    }

    @Test("읽기 실패는 사유를 붙여 보여준다")
    func 읽기_실패() async {
        let store = TestStore(
            initialState: ReplayFeature.State(sessionID: id(0), swingID: id(1))
        ) {
            ReplayFeature(repository: StubRepository(answer: .failure))
        }

        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.failed("디스크를 읽을 수 없습니다")) {
            $0.phase = .failed("기록을 읽지 못했습니다 — 디스크를 읽을 수 없습니다")
        }
    }

    // MARK: 도우미

    private func open(
        _ store: TestStoreOf<ReplayFeature>,
        _ fixture: Fixture,
        index: Int,
        url: String,
        start: TimeInterval
    ) async {
        // 초기 상태가 이미 `.loading`이므로 바뀌는 것이 없다.
        await store.send(.appeared)
        await store.receive(.loaded(fixture.session)) {
            $0.phase = .ready(items: fixture.items, index: index)
            $0.clipURL = URL(filePath: "/clips/\(url)")
            $0.currentSeconds = start
            $0.seek = .init(tick: 1, seconds: start)
            $0.isPlaying = true
        }
    }
}
