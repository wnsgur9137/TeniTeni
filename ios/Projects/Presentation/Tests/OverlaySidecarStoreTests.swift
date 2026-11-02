import CoreGraphics
import Foundation
import Testing
import TeniVision
@testable import Presentation

/// 사이드카 파일을 읽고 쓰는 쪽. 임시 디렉터리에서 돈다 — **실기기가
/// 필요 없다.**
///
/// 여기서 고정하는 것은 네 상태의 구분이다. 섞이면 사용자가 영원히
/// 기다리거나, 고칠 것이 없는데 다시 시도를 누른다.
@Suite("사이드카 저장소")
struct OverlaySidecarStoreTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "overlay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sidecar(
        clipFileName: String = "a.mov",
        version: Int = OverlaySidecar.currentVersion
    ) -> OverlaySidecar {
        OverlaySidecar(
            version: version,
            clipFileName: clipFileName,
            frameRate: 60,
            pixelWidth: 1920,
            pixelHeight: 1080,
            frames: [
                OverlayFrame(
                    seconds: 0,
                    joints: [
                        .rightWrist: PoseJointSample(
                            point: CGPoint(x: 0.5, y: 0.5), confidence: 0.8
                        )
                    ],
                    racketHead: nil
                )
            ]
        )
    }

    @Test("파일이 없으면 분석 전이다")
    func 분석_전() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        #expect(store.state(for: "a.mov") == .notAnalyzed)
    }

    /// 빈 이름은 디렉터리 자신을 가리킨다 — `ClipLocator`와 같은 함정이다.
    @Test("빈 이름은 분석 전으로 떨어진다")
    func 빈_이름() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        #expect(store.state(for: "") == .notAnalyzed)
    }

    @Test("쓰고 나면 읽힌다")
    func 왕복() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        let written = sidecar()
        try store.write(written, for: "a.mov")
        guard case .ready(let read) = store.state(for: "a.mov") else {
            Issue.record("ready가 아니다")
            return
        }
        #expect(read == written)
    }

    /// 모르는 포맷을 "읽을 수 있는 만큼" 읽으면 빠진 필드가 기본값으로
    /// 채워져 **틀린 오버레이를 확신 있게** 보여준다.
    @Test("버전이 다른 사이드카는 실패로 본다")
    func 버전_거부() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        try store.write(sidecar(version: 999), for: "a.mov")
        guard case .failed = store.state(for: "a.mov") else {
            Issue.record("failed가 아니다")
            return
        }
    }

    @Test("다른 클립의 사이드카는 실패로 본다")
    func 짝_불일치() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        // 내용은 b.mov인데 a.mov 자리에 쓴다 — 파일 이동·복원에서 생길 수 있다.
        try store.write(sidecar(clipFileName: "b.mov"), for: "a.mov")
        guard case .failed = store.state(for: "a.mov") else {
            Issue.record("failed가 아니다")
            return
        }
    }

    @Test("깨진 JSON은 실패로 본다 — 분석 전과 구분된다")
    func 깨진_파일() throws {
        let directory = try makeDirectory()
        let store = OverlaySidecarStore(directory: directory)
        try Data("{ 이건 JSON이 아니다".utf8)
            .write(to: directory.appending(path: "a.mov.overlay.json"))
        guard case .failed = store.state(for: "a.mov") else {
            Issue.record("failed가 아니다")
            return
        }
    }

    /// **앱을 닫아도 남아야** 다음에 열었을 때 "분석 전"과 구분된다.
    @Test("실패 기록은 파일로 남는다")
    func 실패_기록() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        store.markFailed("사람을 찾지 못한 프레임이 너무 많습니다", for: "a.mov")
        #expect(store.state(for: "a.mov") == .failed("사람을 찾지 못한 프레임이 너무 많습니다"))
    }

    @Test("성공하면 이전 실패 기록이 지워진다")
    func 실패_해제() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        store.markFailed("실패", for: "a.mov")
        try store.write(sidecar(), for: "a.mov")
        guard case .ready = store.state(for: "a.mov") else {
            Issue.record("ready가 아니다")
            return
        }
    }

    @Test("지우면 사이드카와 실패 기록이 함께 사라진다")
    func 삭제() throws {
        let store = OverlaySidecarStore(directory: try makeDirectory())
        try store.write(sidecar(), for: "a.mov")
        store.markFailed("실패", for: "b.mov")
        store.remove(for: "a.mov")
        store.remove(for: "b.mov")
        #expect(store.state(for: "a.mov") == .notAnalyzed)
        #expect(store.state(for: "b.mov") == .notAnalyzed)
    }
}

@Suite("굽는 큐")
struct OverlayBakeQueueTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 결과가 클립당 결정적이므로 **다시 구울 이유가 없다.**
    @Test("이미 사이드카가 있으면 큐에 넣지 않는다")
    func 중복_방지() async throws {
        let directory = try makeDirectory()
        let store = OverlaySidecarStore(directory: directory)
        try store.write(
            OverlaySidecar(
                clipFileName: "a.mov", frameRate: 60,
                pixelWidth: 1920, pixelHeight: 1080,
                frames: [OverlayFrame(seconds: 0, joints: [:], racketHead: nil)]
            ),
            for: "a.mov"
        )
        let queue = OverlayBakeQueue(
            store: store,
            locator: ClipLocator(directory: directory) { _ in true }
        )
        await queue.enqueue(fileName: "a.mov", side: .right)
        #expect(await queue.isBaking("a.mov") == false)
    }

    @Test("빈 이름은 넣지 않는다")
    func 빈_이름() async throws {
        let directory = try makeDirectory()
        let queue = OverlayBakeQueue(
            store: OverlaySidecarStore(directory: directory),
            locator: ClipLocator(directory: directory) { _ in false }
        )
        await queue.enqueue(fileName: "", side: .right)
        #expect(await queue.isBaking("") == false)
    }

    @Test("같은 클립을 두 번 넣어도 하나다")
    func 같은_클립() async throws {
        let directory = try makeDirectory()
        let queue = OverlayBakeQueue(
            store: OverlaySidecarStore(directory: directory),
            locator: ClipLocator(directory: directory) { _ in false }
        )
        await queue.enqueue(fileName: "a.mov", side: .right)
        await queue.enqueue(fileName: "a.mov", side: .right)
        #expect(await queue.isBaking("a.mov"))
    }

    /// `enqueue`는 **적어만 둔다.** 촬영 중에 돌면 라이브 포즈 추정과 CPU를
    /// 다투고, 그러면 굽는 대상 자체가 사라진다.
    @Test("drain을 부르기 전에는 시작하지 않는다")
    func 적어만_둔다() async throws {
        let directory = try makeDirectory()
        let store = OverlaySidecarStore(directory: directory)
        let queue = OverlayBakeQueue(
            store: store,
            locator: ClipLocator(directory: directory) { _ in false }
        )
        await queue.enqueue(fileName: "a.mov", side: .right)
        // 큐에 있지만 파일은 그대로다.
        #expect(await queue.isBaking("a.mov"))
        #expect(store.state(for: "a.mov") == .notAnalyzed)
    }

    /// 확인과 구독을 나누면 그 사이에 굽기가 끝나 완료 신호를 놓치고
    /// 화면이 "분석 중"에서 **영원히 멈춘다.** 한 번에 받는다.
    @Test("확인과 구독을 한 번에 받는다")
    func 원자적_감시() async throws {
        let directory = try makeDirectory()
        let queue = OverlayBakeQueue(
            store: OverlaySidecarStore(directory: directory),
            locator: ClipLocator(directory: directory) { _ in false }
        )
        await queue.enqueue(fileName: "a.mov", side: .right)

        let (baking, completions) = await queue.watch("a.mov")
        #expect(baking)
        await queue.drain()
        var finished: String?
        for await name in completions where name == "a.mov" {
            finished = name
            break
        }
        #expect(finished == "a.mov")
    }

    @Test("큐에 없는 클립은 감시하지 않는다")
    func 감시_대상_아님() async throws {
        let directory = try makeDirectory()
        let queue = OverlayBakeQueue(
            store: OverlaySidecarStore(directory: directory),
            locator: ClipLocator(directory: directory) { _ in false }
        )
        let (baking, _) = await queue.watch("없는.mov")
        #expect(baking == false)
    }

    /// 파일이 없는 것은 #120이 다루는 상태다. **실패로 적지 않는다** —
    /// 고칠 것이 없는데 "다시 시도"를 띄우게 된다.
    @Test("클립 파일이 없으면 실패로 적지 않는다")
    func 파일_없음() async throws {
        let directory = try makeDirectory()
        let store = OverlaySidecarStore(directory: directory)
        let queue = OverlayBakeQueue(
            store: store,
            locator: ClipLocator(directory: directory) { _ in false }
        )
        await queue.enqueue(fileName: "a.mov", side: .right)
        // ★ 스트림을 **drain보다 먼저** 받는다. 뒤에 받으면 완료 신호가
        //   이미 지나가 영원히 기다린다. `AsyncStream`은 구독자가 생긴
        //   뒤의 yield를 버퍼에 쌓으므로 이 순서면 놓치지 않는다.
        let completions = await queue.completions()
        await queue.drain()
        for await finished in completions where finished == "a.mov" {
            break
        }
        #expect(store.state(for: "a.mov") == .notAnalyzed)
    }
}
