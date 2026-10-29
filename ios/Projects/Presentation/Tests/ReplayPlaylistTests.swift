import Domain
import Foundation
import Testing
@testable import Presentation

/// 플레이리스트는 **펼치기만** 한다. 정렬은 저장소가 이미 했다.
@Suite("리플레이 플레이리스트")
struct ReplayPlaylistTests {

    private func swing(_ start: TimeInterval) -> Swing {
        Swing(startSeconds: start, endSeconds: start + 1.2, impactSeconds: start + 0.5)
    }

    private func session(_ clips: [(name: String, fps: Int, swings: [Swing])]) -> Session {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return Session(
            startedAt: start,
            situation: .ballMachine,
            fps: 120,
            clips: clips.enumerated().map { index, clip in
                Clip(
                    fileName: clip.name,
                    recordedAt: start.addingTimeInterval(Double(index) * 10),
                    fps: clip.fps,
                    swings: clip.swings
                )
            }
        )
    }

    @Test("클립 경계를 넘어 한 줄로 펼친다")
    func 펼치기() {
        let items = ReplayItem.playlist(from: session([
            (name: "a.mov", fps: 120, swings: [swing(0), swing(2)]),
            (name: "b.mov", fps: 60, swings: [swing(1)]),
        ]))

        #expect(items.count == 3)
        #expect(items.map(\.fileName) == ["a.mov", "a.mov", "b.mov"])
        // 번호는 **세션 전체** 기준이다. 클립마다 1부터 다시 세면 사용자가
        // "12번째 스윙"을 말할 수 없다.
        #expect(items.map(\.position) == [1, 2, 3])
        #expect(items.allSatisfy { $0.total == 3 })
    }

    @Test("fps는 클립마다 따로 들고 온다")
    func 클립별_fps() {
        let items = ReplayItem.playlist(from: session([
            (name: "a.mov", fps: 120, swings: [swing(0)]),
            (name: "b.mov", fps: 60, swings: [swing(0)]),
        ]))

        // 발열로 강등되면 클립마다 다르다(ADR-0005). 세션의 값(120)을
        // 쓰면 두 번째 클립의 "프레임 하나"가 절반으로 틀린다.
        #expect(items.map(\.clipFPS) == [120, 60])
        #expect(items[0].frameSeconds == 1.0 / 120)
        #expect(items[1].frameSeconds == 1.0 / 60)
    }

    @Test("스윙이 없는 클립은 칸을 만들지 않는다")
    func 빈_클립_섞임() {
        let items = ReplayItem.playlist(from: session([
            (name: "a.mov", fps: 120, swings: []),
            (name: "b.mov", fps: 120, swings: [swing(0)]),
            (name: "c.mov", fps: 120, swings: []),
        ]))

        #expect(items.count == 1)
        #expect(items[0].fileName == "b.mov")
        #expect(items[0].position == 1)
    }

    @Test("스윙이 하나도 없으면 빈 플레이리스트다")
    func 빈_세션() {
        #expect(ReplayItem.playlist(from: session([])).isEmpty)
        #expect(ReplayItem.playlist(from: session([(name: "a.mov", fps: 120, swings: [])])).isEmpty)
    }

    @Test("저장소가 준 순서를 바꾸지 않는다")
    func 재정렬_없음() {
        // 일부러 역순으로 넣는다. 플레이리스트가 다시 정렬하면 이 기대가
        // 깨진다 — 정렬은 저장소 한 곳에만 있어야 한다.
        let items = ReplayItem.playlist(from: session([
            (name: "a.mov", fps: 120, swings: [swing(5), swing(0)]),
        ]))

        #expect(items.map { $0.swing.startSeconds } == [5, 0])
    }

    @Test("fps가 0이어도 프레임 길이를 0으로 나누지 않는다")
    func fps_0_방어() {
        let items = ReplayItem.playlist(from: session([
            (name: "a.mov", fps: 0, swings: [swing(0)]),
        ]))

        #expect(items[0].frameSeconds == 1.0 / 30)
    }
}
