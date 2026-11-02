import Domain
import Foundation
import TeniVision

/// 클립을 하나씩 구워 사이드카를 남긴다.
///
/// ## 왜 큐인가
///
/// 세션 하나가 클립 수십 개를 남긴다. 동시에 구우면 CPU를 전부 먹고, 그
/// 사이 사용자는 요약 화면에서 아무것도 못 한다. **직렬로 하나씩** 돌린다.
///
/// ## 왜 촬영 중에 돌리지 않는가
///
/// 라이브 포즈 추정과 CPU를 다투면 스윙 트리거가 신호를 잃는다. 그러면
/// 굽는 대상 자체가 사라진다 — 가장 나쁜 교환이다.
///
/// `enqueue`는 **적어만 두고** `drain`이 시작한다. 촬영이 끝난 뒤 호출부가
/// `drain`을 부른다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md 선택지 2
public actor OverlayBakeQueue {

    private let baker: OverlayBaker
    private let store: OverlaySidecarStore
    private let locator: ClipLocator

    private var queued: [(fileName: String, side: RacketSide)] = []
    private var inFlight: String?
    private var running: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<String>.Continuation] = [:]

    public init(
        baker: OverlayBaker = OverlayBaker(),
        store: OverlaySidecarStore = OverlaySidecarStore(),
        locator: ClipLocator = ClipLocator()
    ) {
        self.baker = baker
        self.store = store
        self.locator = locator
    }

    /// 굽을 클립을 적어 둔다. **시작하지 않는다.**
    ///
    /// 이미 사이드카가 있으면 넣지 않는다 — 결과가 클립당 결정적이므로
    /// 다시 구울 이유가 없다.
    public func enqueue(fileName: String, side: RacketSide) {
        guard !fileName.isEmpty else { return }
        guard !queued.contains(where: { $0.fileName == fileName }) else { return }
        guard inFlight != fileName else { return }
        if case .ready = store.state(for: fileName) { return }
        queued.append((fileName, side))
    }

    /// 적어 둔 것을 하나씩 굽는다. 이미 돌고 있으면 아무것도 하지 않는다.
    public func drain() {
        guard running == nil else { return }
        running = Task { [weak self] in
            await self?.process()
        }
    }

    /// 실패한 클립을 다시 굽는다. 화면의 "다시 시도"가 부른다.
    public func retry(fileName: String, side: RacketSide) {
        guard !fileName.isEmpty else { return }
        queued.removeAll { $0.fileName == fileName }
        queued.insert((fileName, side), at: 0)
        drain()
    }

    /// 굽는 중이거나 굽기를 기다리는가.
    public func isBaking(_ fileName: String) -> Bool {
        inFlight == fileName || queued.contains { $0.fileName == fileName }
    }

    /// 굽는 중인지 **확인하면서 동시에** 완료 스트림을 받는다.
    ///
    /// ## 왜 두 호출로 나누지 않는가
    ///
    /// `isBaking`을 먼저 묻고 `completions`를 나중에 받으면 그 사이에 굽기가
    /// 끝날 수 있다. 그러면 완료 신호가 이미 지나가 **화면이 "분석 중"에서
    /// 영원히 멈춘다.** 순서를 바꿔도 반대 방향으로 틀린다 — 다 끝났는데
    /// "분석 전"이라고 말한다.
    ///
    /// 액터 메서드 하나로 묶으면 그 사이에 아무것도 끼지 못한다.
    public func watch(_ fileName: String) -> (isBaking: Bool, completions: AsyncStream<String>) {
        (isBaking(fileName), completions())
    }

    /// 한 클립이 끝날 때마다 그 이름을 내는 스트림.
    ///
    /// 화면이 "분석 중"을 보여주는 동안 이것을 듣는다. 폴링하지 않는 이유는
    /// 분명하다 — 굽는 데 수십 초가 걸릴 수 있고, 그동안 1초마다 파일을
    /// 열어보면 디스크를 긁으면서 배터리를 쓴다.
    public func completions() -> AsyncStream<String> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func process() async {
        while !queued.isEmpty {
            let next = queued.removeFirst()
            inFlight = next.fileName
            await bake(next.fileName, side: next.side)
            inFlight = nil
            for continuation in listeners.values {
                continuation.yield(next.fileName)
            }
        }
        running = nil
    }

    private func bake(_ fileName: String, side: RacketSide) async {
        guard let url = locator.url(for: fileName) else {
            // 파일이 없다. #120이 다루는 상태이고, 여기서는 **실패로 적지
            // 않는다** — 고칠 것이 없는데 "다시 시도"를 띄우게 된다.
            return
        }
        do {
            let sidecar = try await baker.bake(clipAt: url, side: side)
            try store.write(sidecar, for: fileName)
        } catch OverlayBakeError.noPoseFound {
            store.markFailed("사람을 찾지 못한 프레임이 너무 많습니다", for: fileName)
        } catch {
            store.markFailed("오버레이를 만들지 못했습니다 — \(error.localizedDescription)", for: fileName)
        }
    }
}
