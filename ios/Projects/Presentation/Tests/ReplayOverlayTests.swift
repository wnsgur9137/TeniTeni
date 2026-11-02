import ComposableArchitecture
import Domain
import Foundation
import Testing
import TeniVision
@testable import Presentation

private struct OverlayStubRepository: SessionRepository {
    let session: Session
    func save(_ session: Session) async throws {}
    func loadAll() async throws -> [Session] { [] }
    func delete(id: UUID) async throws {}
    func load(id: UUID) async throws -> Session? { session }
}

private func oid(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
}

/// 오버레이 모드 전환과 사이드카 상태. **사이드카 데이터는 리듀서에 없다** —
/// 여기서 고정하는 것은 "무엇을 켤 수 있고 무엇을 말하는가"다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md
@Suite("리플레이 오버레이")
@MainActor
struct ReplayOverlayTests {

    private static func session() -> Session {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return Session(
            id: oid(0),
            startedAt: start,
            situation: .ballMachine,
            fps: 120,
            clips: [
                Clip(
                    id: oid(10),
                    fileName: "a.mov",
                    recordedAt: start,
                    fps: 120,
                    swings: [Swing(id: oid(1), startSeconds: 1, endSeconds: 3, impactSeconds: 2)]
                )
            ]
        )
    }

    private func makeStore(
        overlay: OverlayLayer = .off,
        phase: ReplayFeature.OverlayPhase = .ready,
        present: Set<String> = ["a.mov"]
    ) -> TestStoreOf<ReplayFeature> {
        TestStore(
            initialState: ReplayFeature.State(
                sessionID: oid(0),
                swingID: oid(1),
                phase: .ready(items: ReplayItem.playlist(from: Self.session()), index: 0),
                clipURL: present.contains("a.mov") ? URL(filePath: "/clips/a.mov") : nil,
                overlay: overlay,
                overlayPhase: phase,
                side: .right
            )
        ) {
            ReplayFeature(
                repository: OverlayStubRepository(session: Self.session()),
                locator: ClipLocator(directory: URL(filePath: "/clips")) {
                    present.contains($0.lastPathComponent)
                }
            )
        }
    }

    // MARK: - 기본값

    /// 리플레이의 첫 화면은 **자기 스윙 영상**이어야 한다. 오버레이는
    /// 사용자가 "보고 싶다"고 말한 뒤에 올라온다.
    @Test("기본은 끔이다")
    func 기본값() {
        let state = ReplayFeature.State(sessionID: oid(0), swingID: oid(1))
        #expect(state.overlay == .off)
        #expect(state.canDrawOverlay == false)
        #expect(UserPreferences().lastOverlayLayer == .off)
    }

    // MARK: - 전환

    @Test("켜면 코디네이터에게 기억해 달라고 알린다")
    func 전환() async {
        let store = makeStore()
        await store.send(.overlaySelected(.skeleton)) { $0.overlay = .skeleton }
        await store.receive(.delegate(.overlayChanged(.skeleton)))
        #expect(store.state.canDrawOverlay)
    }

    @Test("같은 레이어를 다시 누르면 아무 일도 없다")
    func 같은_레이어() async {
        let store = makeStore(overlay: .skeleton)
        await store.send(.overlaySelected(.skeleton))
    }

    /// 바뀐 것처럼 보이고 아무것도 안 그려지면 **고장으로 읽힌다.**
    @Test("사이드카가 없으면 켜지지 않는다")
    func 못_켠다() async {
        for phase in [
            ReplayFeature.OverlayPhase.notAnalyzed,
            .baking,
            .failed("사람을 찾지 못했습니다"),
        ] {
            let store = makeStore(phase: phase)
            #expect(store.state.canSelectOverlay == false)
            await store.send(.overlaySelected(.skeleton))
        }
    }

    /// 끄는 것은 언제나 된다. 못 끄게 하면 켜진 채로 갇힌다.
    @Test("끄는 것은 사이드카가 없어도 된다")
    func 끄기() async {
        let store = makeStore(overlay: .skeleton, phase: .ready)
        await store.send(.overlayPhaseChanged(.notAnalyzed)) {
            $0.overlayPhase = .notAnalyzed
            // 그릴 수 없게 됐으면 **끈다.**
            $0.overlay = .off
        }
        await store.send(.overlaySelected(.off))
    }

    @Test("영상이 없으면 켜지지 않는다")
    func 영상_없음() async {
        let store = makeStore(phase: .ready, present: [])
        #expect(store.state.isClipMissing)
        #expect(store.state.canSelectOverlay == false)
        await store.send(.overlaySelected(.racket))
    }

    // MARK: - 상태가 바뀔 때

    /// 켜진 채로 두면 아무것도 안 그려지는 화면에서 세그먼트만
    /// "스켈레톤"을 가리킨다.
    @Test("그릴 수 없게 되면 자동으로 꺼진다")
    func 자동_끄기() async {
        let store = makeStore(overlay: .racket, phase: .ready)
        await store.send(.overlayPhaseChanged(.failed("사람을 찾지 못했습니다"))) {
            $0.overlayPhase = .failed("사람을 찾지 못했습니다")
            $0.overlay = .off
        }
    }

    @Test("꺼져 있으면 상태만 바뀐다")
    func 꺼짐_유지() async {
        let store = makeStore(overlay: .off, phase: .ready)
        await store.send(.overlayPhaseChanged(.baking)) { $0.overlayPhase = .baking }
        #expect(store.state.overlay == .off)
    }

    // MARK: - 다시 시도

    @Test("실패일 때만 다시 시도가 간다")
    func 다시_시도() async {
        let store = makeStore(phase: .failed("사람을 찾지 못했습니다"))
        await store.send(.overlayRetryTapped) { $0.overlayPhase = .baking }
        await store.receive(.delegate(.overlayRetryRequested(fileName: "a.mov", side: .right)))
    }

    @Test("실패가 아니면 다시 시도가 가지 않는다")
    func 다시_시도_무효() async {
        for phase in [ReplayFeature.OverlayPhase.ready, .baking, .notAnalyzed] {
            let store = makeStore(phase: phase)
            await store.send(.overlayRetryTapped)
        }
    }

    // MARK: - 화면이 읽는 문구

    /// **네 상태를 섞지 않는다.** 실패를 "준비 중"으로 보여주면 사용자는
    /// 영원히 기다리고, "분석 전"을 실패로 보여주면 고칠 것이 없는데
    /// 다시 시도를 누른다.
    @Test("상태마다 다른 문구를 낸다")
    func 문구() {
        #expect(makeStore(phase: .ready).state.overlayNotice == nil)
        #expect(makeStore(phase: .baking).state.overlayNotice == "오버레이를 준비하고 있습니다")
        #expect(makeStore(phase: .notAnalyzed).state.overlayNotice == "아직 분석하지 않았습니다")
        #expect(
            makeStore(phase: .failed("사람을 찾지 못했습니다")).state.overlayNotice
                == "사람을 찾지 못했습니다"
        )
        // 영상이 없으면 그 사실이 먼저다 — 사이드카 상태를 말해도 소용없다.
        #expect(
            makeStore(phase: .ready, present: []).state.overlayNotice
                == "영상이 없어 오버레이도 없습니다"
        )
    }

    @Test("레이어 이름과 사이드카 필요 여부")
    func 레이어_값() {
        #expect(OverlayLayer.off.title == "끔")
        #expect(OverlayLayer.skeleton.title == "스켈레톤")
        #expect(OverlayLayer.racket.title == "라켓 궤적")
        #expect(OverlayLayer.off.needsSidecar == false)
        #expect(OverlayLayer.skeleton.needsSidecar)
        #expect(OverlayLayer.racket.needsSidecar)
        // 볼 궤적·라인은 **case를 두지 않는다.** 그릴 수 없는 모드를
        // UI가 그리게 되고 죽은 분기가 생긴다.
        #expect(OverlayLayer.allCases.count == 3)
    }

    /// 저장된 JSON에 새 키가 없는 **기존 사용자**의 설정이다. 디코딩이
    /// 통째로 실패하면 손잡이·소리 설정까지 초기화된다.
    @Test("설정에 오버레이 키가 없어도 나머지가 살아남는다")
    func 구_설정_호환() throws {
        let old = """
            {"handedness":"left","lastSituation":"wall","lastObservable":"swing","soundEnabled":false}
            """
        let decoded = try JSONDecoder().decode(
            UserPreferences.self, from: Data(old.utf8)
        )
        #expect(decoded.handedness == .left)
        #expect(decoded.soundEnabled == false)
        #expect(decoded.lastOverlayLayer == .off)
    }
}
