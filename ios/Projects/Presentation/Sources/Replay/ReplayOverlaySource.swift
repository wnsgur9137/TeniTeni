import Domain
import Foundation
import Observation
import TeniVision

/// 지금 보는 클립의 사이드카를 들고 있다.
///
/// ## 왜 리듀서가 아니라 여기인가
///
/// 사이드카는 프레임 수백 개 × 관절 19개다. 리듀서 상태에 두면 액션마다
/// 그 배열을 `==`로 비교한다 — 시각 관측이 초당 수십 번 오므로 비교가
/// 계속 돈다. `AVPlayer`를 화면이 소유하는 것과 같은 이유다
/// (SPEC-0123 선택지 7).
///
/// 리듀서에는 **상태만** 올려보낸다(`ReplayFeature.OverlayPhase`).
///
/// ## 큐 투입도 여기서 한다
///
/// 상태 변경(리듀서)과 큐 투입(코디네이터 이펙트)으로 갈라 두면, 상태에
/// 붙은 감시가 투입보다 먼저 달려 **"큐에 없다"를 읽고 "분석 전"으로
/// 되돌린다.** 둘을 한 Task에 묶는다.
@MainActor
@Observable
public final class ReplayOverlaySource {

    /// 지금 클립의 사이드카. 없으면 `nil`이다.
    public private(set) var sidecar: OverlaySidecar?

    /// 상태가 바뀌면 리듀서에 알린다.
    public var onPhase: (@MainActor (ReplayFeature.OverlayPhase) -> Void)?

    private let store: OverlaySidecarStore
    private let queue: OverlayBakeQueue
    private var fileName: String?
    private var side: RacketSide = .right
    private var work: Task<Void, Never>?

    public init(
        store: OverlaySidecarStore = OverlaySidecarStore(),
        queue: OverlayBakeQueue
    ) {
        self.store = store
        self.queue = queue
    }

    // `deinit`에서 `work`를 취소하지 않는다. nonisolated deinit은 메인 액터
    // 프로퍼티를 읽을 수 없고, 읽으려고 `Task`를 띄우면 그 Task가 해제된
    // 자신을 캡처한다.
    //
    // 취소하지 않아도 새는 것이 없다: 감시 Task는 `[weak self]`로 잡으므로
    // 이 객체를 붙들지 않고, `completions()` 스트림은 continuation이
    // 사라질 때 스스로 끝난다.

    /// 클립이 바뀌었다. 사이드카를 다시 읽고, **없으면 굽기를 시작한다.**
    ///
    /// 같은 파일이면 아무것도 하지 않는다 — 같은 클립 안의 다음 스윙으로
    /// 넘어갈 때마다 수백 프레임을 다시 파싱할 이유가 없다.
    public func load(fileName new: String?, side: RacketSide) {
        self.side = side
        guard fileName != new else { return }
        fileName = new
        work?.cancel()
        work = nil
        sidecar = nil

        guard let new, !new.isEmpty else {
            onPhase?(.notAnalyzed)
            return
        }
        start(new, retrying: false)
    }

    /// "다시 시도". 큐에 **넣고 나서** 감시한다 — 순서가 뒤집히면
    /// "분석 전"으로 되돌아간다.
    public func retry() {
        guard let fileName else { return }
        work?.cancel()
        start(fileName, retrying: true)
    }

    /// 파일을 읽고, 필요하면 굽기를 시작하고, 끝날 때까지 듣는다.
    ///
    /// **전부 한 Task 안에서 한다.** 나누면 그 사이에 상태가 바뀌어
    /// 어긋난다.
    private func start(_ name: String, retrying: Bool) {
        let store = store
        work = Task { [weak self] in
            guard let self else { return }

            // ★ 디코딩을 메인 액터 밖에서 한다. 23k 점짜리 JSON을 여기서
            //   풀면 그만큼 화면이 멈춘다.
            let state = await Self.read(name, from: store)
            guard !Task.isCancelled else { return }

            switch state {
            case .ready(let loaded):
                sidecar = loaded
                onPhase?(.ready)
                return

            case .failed(let reason) where !retrying:
                onPhase?(.failed(reason))
                return

            case .baking, .notAnalyzed, .failed:
                break
            }

            // 파일에 없다. 굽게 만든다.
            //
            // ★ **보관함에서 연 세션이 여기로 온다.** 촬영 종료만으로 큐에
            //   넣으면 어제 찍은 세션은 영원히 "분석 전"이고, 세그먼트는
            //   비활성이며 "다시 시도"는 실패에만 뜬다 — 탈출구가 없다.
            //   강제 종료로 굽기가 끊긴 클립도 같다.
            if retrying {
                await queue.retry(fileName: name, side: side)
            } else {
                await queue.enqueue(fileName: name, side: side)
                await queue.drain()
            }
            guard !Task.isCancelled else { return }

            // 확인과 구독을 **한 번에** 받는다. 나누면 그 사이에 굽기가
            // 끝나 완료 신호를 놓치고 "분석 중"에서 영원히 멈춘다.
            let (baking, completions) = await queue.watch(name)
            guard !Task.isCancelled else { return }

            guard baking else {
                // 큐에 없다. **"분석 전"으로 단정하지 않는다** — 그 사이에
                // 끝났을 수 있다. 파일이 정본이다.
                await report(name, from: store)
                return
            }
            onPhase?(.baking)

            for await finished in completions {
                guard !Task.isCancelled else { return }
                guard finished == name else { continue }
                await report(name, from: store)
                return
            }
        }
    }

    /// 파일을 읽어 상태를 올려보낸다.
    private func report(_ name: String, from store: OverlaySidecarStore) async {
        let state = await Self.read(name, from: store)
        guard !Task.isCancelled else { return }
        switch state {
        case .ready(let loaded):
            sidecar = loaded
            onPhase?(.ready)
        case .failed(let reason):
            onPhase?(.failed(reason))
        case .baking, .notAnalyzed:
            onPhase?(.notAnalyzed)
        }
    }

    /// 메인 액터 밖에서 파일을 읽는다.
    ///
    /// `nonisolated`로 둔 `static`이라 이 클래스의 메인 액터 격리를 타지
    /// 않는다. `OverlaySidecarStore`는 `Sendable`이다.
    private nonisolated static func read(
        _ name: String,
        from store: OverlaySidecarStore
    ) async -> OverlaySidecarState {
        await Task.detached(priority: .userInitiated) {
            store.state(for: name)
        }.value
    }

    /// 그릴 프레임. 사이드카가 없거나 그 시각에 데이터가 없으면 `nil`이다.
    public func frame(at seconds: TimeInterval) -> OverlayFrame? {
        sidecar?.frame(at: seconds)
    }

    /// 라켓 궤적을 그릴 과거 구간.
    ///
    /// 계산은 `OverlaySidecar`가 한다 — **값 타입이라 검증된다.** 여기에
    /// 두면 `@MainActor @Observable` 안에 갇혀 테스트가 닿지 못한다.
    public func racketTrail(
        until seconds: TimeInterval,
        trail: TimeInterval
    ) -> [RacketHead?] {
        sidecar?.racketTrail(until: seconds, trail: trail) ?? []
    }
}
