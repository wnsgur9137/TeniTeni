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
    private var watching: Task<Void, Never>?

    public init(
        store: OverlaySidecarStore = OverlaySidecarStore(),
        queue: OverlayBakeQueue
    ) {
        self.store = store
        self.queue = queue
    }

    // `deinit`에서 `watching`을 취소하지 않는다. nonisolated deinit은 메인
    // 액터 프로퍼티를 읽을 수 없고, 읽으려고 `Task`를 띄우면 그 Task가
    // 해제된 자신을 캡처한다.
    //
    // 취소하지 않아도 새는 것이 없다: 감시 Task는 `[weak self]`로 잡으므로
    // 이 객체를 붙들지 않고, `completions()` 스트림은 continuation이
    // 사라질 때 스스로 끝난다.

    /// 클립이 바뀌었다. 사이드카를 다시 읽는다.
    ///
    /// 같은 파일이면 아무것도 하지 않는다 — 같은 클립 안의 다음 스윙으로
    /// 넘어갈 때마다 수백 프레임을 다시 파싱할 이유가 없다.
    public func load(fileName new: String?) {
        guard fileName != new else { return }
        fileName = new
        watching?.cancel()
        watching = nil
        sidecar = nil

        guard let new, !new.isEmpty else {
            onPhase?(.notAnalyzed)
            return
        }
        refresh(new)
    }

    /// 파일 상태를 다시 읽는다. 큐가 끝났다고 알리면 이것이 돈다.
    private func refresh(_ name: String) {
        switch store.state(for: name) {
        case .ready(let loaded):
            sidecar = loaded
            onPhase?(.ready)

        case .failed(let reason):
            sidecar = nil
            onPhase?(.failed(reason))

        case .baking, .notAnalyzed:
            sidecar = nil
            // 파일에는 없다. 큐가 들고 있는지 물어본다 — 파일만 보면
            // "굽는 중"과 "분석 전"이 구분되지 않는다.
            watch(name)
        }
    }

    /// 큐에 있으면 `baking`으로 두고 끝날 때까지 듣는다.
    ///
    /// 폴링하지 않는다. 굽는 데 수십 초가 걸릴 수 있고, 그동안 파일을
    /// 반복해 열면 디스크를 긁으며 배터리를 쓴다.
    private func watch(_ name: String) {
        watching = Task { [weak self] in
            guard let self else { return }
            // ★ 확인과 구독을 **한 번에** 받는다. 나누면 그 사이에 굽기가
            //   끝나 완료 신호를 놓치고 "분석 중"에서 영원히 멈춘다.
            let (baking, completions) = await queue.watch(name)
            guard !Task.isCancelled else { return }
            onPhase?(baking ? .baking : .notAnalyzed)
            guard baking else { return }

            for await finished in completions {
                guard !Task.isCancelled else { return }
                guard finished == name else { continue }
                // 끝났다. 파일을 다시 읽는다 — 성공인지 실패인지는
                // 파일이 말한다.
                switch store.state(for: name) {
                case .ready(let loaded):
                    sidecar = loaded
                    onPhase?(.ready)
                case .failed(let reason):
                    onPhase?(.failed(reason))
                case .baking, .notAnalyzed:
                    onPhase?(.notAnalyzed)
                }
                return
            }
        }
    }

    /// 다시 시도 뒤 상태를 `baking`으로 두고 다시 듣는다.
    public func watchAgain() {
        guard let fileName else { return }
        watching?.cancel()
        watch(fileName)
    }

    /// 그릴 프레임. 사이드카가 없거나 그 시각에 데이터가 없으면 `nil`이다.
    public func frame(at seconds: TimeInterval) -> OverlayFrame? {
        sidecar?.frame(at: seconds)
    }

    /// 라켓 궤적을 그릴 과거 구간.
    ///
    /// - Parameter trail: 지금 시각에서 **뒤로** 몇 초를 보여줄지.
    public func racketTrail(
        until seconds: TimeInterval,
        trail: TimeInterval
    ) -> [RacketHead?] {
        guard let sidecar else { return [] }
        return sidecar.frames
            .filter { $0.seconds <= seconds && $0.seconds >= seconds - trail }
            .map(\.racketHead)
    }
}
