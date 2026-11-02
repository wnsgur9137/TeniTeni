import ComposableArchitecture
import Domain
import Foundation
import TeniVision

/// 스윙 리플레이. **AVFoundation을 모른다.**
///
/// 배속·인덱스·스크러버 위치·전체화면은 전부 여기와 값 타입 안에 있고,
/// `AVPlayer` 명령은 `ReplayPlayer`가 받는다. 그래서 이 화면의 동작이
/// 시뮬레이터에서 영상을 재생하지 않고도 `TestStore`로 고정된다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 7.
@Reducer
public struct ReplayFeature {

    /// 플레이어에게 보내는 **선언적** 명령. `tick`이 바뀌면 화면이 그것을
    /// 플레이어에 전달한다. 명령을 상태로 두면 리듀서가 순수하게 남는다.
    public struct SeekCommand: Equatable, Sendable {
        public var tick: Int
        public var seconds: TimeInterval

        public init(tick: Int = 0, seconds: TimeInterval = 0) {
            self.tick = tick
            self.seconds = seconds
        }
    }

    public struct StepCommand: Equatable, Sendable {
        public var tick: Int
        public var count: Int

        public init(tick: Int = 0, count: Int = 0) {
            self.tick = tick
            self.count = count
        }
    }

    @ObservableState
    public struct State: Equatable {
        public let sessionID: UUID
        /// 어느 스윙으로 열 것인가. 목록에 없으면 첫 칸으로 떨어진다.
        public let swingID: UUID

        public var phase: Phase
        public var speed: PlaybackSpeed
        public var isPlaying: Bool
        public var isFullscreen: Bool
        /// 현재 재생 위치. **클립 기준 절대초**다.
        public var currentSeconds: TimeInterval
        /// 이 클립의 영상 파일. `nil`이면 파일이 없다.
        public var clipURL: URL?
        /// `canPlaySlowForward == false`인 클립. 배속을 막고 사유를 적는다.
        public var slowMotionUnsupported: Bool

        /// 지금 켜진 오버레이. 기본은 `off` — **첫 화면은 자기 스윙 영상이다.**
        public var overlay: OverlayLayer
        /// 이 클립의 사이드카가 어떤 상태인가. **데이터는 들지 않는다** —
        /// 프레임 수백 개를 리듀서 상태에 두면 액션마다 그 배열을 비교한다.
        /// 데이터는 `ReplayOverlaySource`가 들고, 여기엔 상태만 온다
        /// (`AVPlayer`를 화면이 소유하는 것과 같은 이유다 — SPEC-0123 선택지 7).
        public var overlayPhase: OverlayPhase
        /// 라켓을 든 쪽. 추정식이 어느 손을 볼지 정한다.
        public let side: RacketSide

        public var seek: SeekCommand
        public var step: StepCommand

        public init(
            sessionID: UUID,
            swingID: UUID,
            phase: Phase = .loading,
            speed: PlaybackSpeed = .standard,
            isPlaying: Bool = false,
            isFullscreen: Bool = false,
            currentSeconds: TimeInterval = 0,
            clipURL: URL? = nil,
            slowMotionUnsupported: Bool = false,
            overlay: OverlayLayer = .off,
            overlayPhase: OverlayPhase = .notAnalyzed,
            side: RacketSide = .right,
            seek: SeekCommand = SeekCommand(),
            step: StepCommand = StepCommand()
        ) {
            self.sessionID = sessionID
            self.swingID = swingID
            self.phase = phase
            self.speed = speed
            self.isPlaying = isPlaying
            self.isFullscreen = isFullscreen
            self.currentSeconds = currentSeconds
            self.clipURL = clipURL
            self.slowMotionUnsupported = slowMotionUnsupported
            self.overlay = overlay
            self.overlayPhase = overlayPhase
            self.side = side
            self.seek = seek
            self.step = step
        }

        public var items: [ReplayItem] {
            guard case .ready(let items, _) = phase else { return [] }
            return items
        }

        public var index: Int? {
            guard case .ready(_, let index) = phase else { return nil }
            return index
        }

        public var current: ReplayItem? {
            guard case .ready(let items, let index) = phase,
                  items.indices.contains(index)
            else { return nil }
            return items[index]
        }

        public var scrubber: ReplayScrubber? {
            current.map { ReplayScrubber(swing: $0.swing) }
        }

        /// 파일이 없어 재생할 수 없다. **넘기기는 살아 있다** — 건너뛰면
        /// "34개 중 12번째"의 분모가 달라져 사용자가 세던 수와 어긋난다.
        public var isClipMissing: Bool { current != nil && clipURL == nil }

        public var canGoPrevious: Bool { (index ?? 0) > 0 }

        public var canGoNext: Bool {
            guard let index else { return false }
            return index + 1 < items.count
        }

        public var effectiveSpeed: PlaybackSpeed {
            slowMotionUnsupported ? .normal : speed
        }

        /// 지금 오버레이를 그릴 수 있는가.
        public var canDrawOverlay: Bool {
            overlay.needsSidecar && overlayPhase == .ready
        }

        /// 세그먼트를 눌러도 되는가.
        ///
        /// 사이드카가 없으면 **못 누르게 하되 숨기지는 않는다.** 숨기면
        /// "이 앱에 오버레이가 없다"로 읽히고 그 오해는 되돌리기 어렵다.
        public var canSelectOverlay: Bool {
            overlayPhase == .ready && !isClipMissing
        }

        /// 세그먼트 옆에 적는 한 줄. 켤 수 있으면 `nil`이다.
        public var overlayNotice: String? {
            if isClipMissing { return "영상이 없어 오버레이도 없습니다" }
            switch overlayPhase {
            case .ready: return nil
            case .baking: return "오버레이를 준비하고 있습니다"
            case .notAnalyzed: return "아직 분석하지 않았습니다"
            case .failed(let reason): return reason
            }
        }
    }

    /// 사이드카가 지금 어떤 상태인가. **데이터는 담지 않는다.**
    ///
    /// 네 상태를 섞지 않는 이유: 실패를 "준비 중"으로 보여주면 사용자는
    /// 영원히 기다리고, "분석 전"을 실패로 보여주면 고칠 것이 없는데
    /// 다시 시도를 누른다.
    public enum OverlayPhase: Equatable, Sendable {
        case ready
        case baking
        case failed(String)
        case notAnalyzed
    }

    public enum Phase: Equatable, Sendable {
        case loading
        case ready(items: [ReplayItem], index: Int)
        case failed(String)
    }

    public enum Action: Equatable {
        case appeared
        case loaded(Session)
        case failed(String)
        case missing

        case playPauseTapped
        case speedSelected(PlaybackSpeed)
        case stepTapped(Int)
        case impactTapped
        case scrubbed(Double)
        case previousTapped
        case nextTapped
        case fullscreenToggled
        case retryTapped
        case closeTapped

        case overlaySelected(OverlayLayer)
        case overlayRetryTapped

        /// 플레이어가 올려보내는 것
        case timeObserved(TimeInterval)
        case reachedEnd
        case slowMotionUnsupported(Bool)
        case overlayPhaseChanged(OverlayPhase)

        case delegate(Delegate)

        public enum Delegate: Equatable {
            case closed
            /// 고른 레이어를 기억해 달라. 저장은 코디네이터의 일이다 —
            /// `Presentation`의 Feature는 설정 저장소를 모른다(D-03).
            case overlayChanged(OverlayLayer)
            /// 이 클립을 다시 구워 달라.
            case overlayRetryRequested(fileName: String, side: RacketSide)
        }
    }

    private let repository: any SessionRepository
    private let locator: ClipLocator

    public init(repository: any SessionRepository, locator: ClipLocator = ClipLocator()) {
        self.repository = repository
        self.locator = locator
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared, .retryTapped:
                state.phase = .loading
                let id = state.sessionID
                let repository = repository
                return .run { send in
                    do {
                        guard let session = try await repository.load(id: id) else {
                            await send(.missing)
                            return
                        }
                        await send(.loaded(session))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .loaded(let session):
                let items = ReplayItem.playlist(from: session)
                guard !items.isEmpty else {
                    // 요약이 스윙 0개를 진단 화면으로 받으므로 도달할 수
                    // 없다. 그래도 상태로 막는다.
                    state.phase = .failed("이 세션에는 스윙이 없습니다")
                    return .none
                }
                let index = items.firstIndex { $0.swing.id == state.swingID } ?? 0
                state.phase = .ready(items: items, index: index)
                move(to: index, from: nil, in: &state)
                // 열면 바로 돈다. 리플레이를 여는 행위 자체가 "보여달라"다.
                state.isPlaying = !state.isClipMissing
                return .none

            case .failed(let reason):
                state.phase = .failed("기록을 읽지 못했습니다 — \(reason)")
                return .none

            case .missing:
                state.phase = .failed("이 세션의 기록이 없습니다")
                return .none

            case .playPauseTapped:
                guard !state.isClipMissing else { return .none }
                state.isPlaying.toggle()
                return .none

            case .speedSelected(let speed):
                // 지원하지 않는 클립에서 칩을 눌러도 바뀌지 않는다. 바뀐 것처럼
                // 보이고 1×로 재생하면 "느리게 안 된다"를 영상으로 오해한다.
                guard !state.slowMotionUnsupported || speed == .normal else { return .none }
                state.speed = speed
                return .none

            case .stepTapped(let count):
                guard !state.isClipMissing, count != 0 else { return .none }
                // 재생과 스텝이 섞이면 어디로 갔는지 알 수 없다.
                state.isPlaying = false
                state.step.tick += 1
                state.step.count = count
                return .none

            case .impactTapped:
                guard let scrubber = state.scrubber, !state.isClipMissing else { return .none }
                state.isPlaying = false
                return seek(to: scrubber.impact, in: &state)

            case .scrubbed(let fraction):
                guard let scrubber = state.scrubber, !state.isClipMissing else { return .none }
                return seek(to: scrubber.seconds(atFraction: fraction), in: &state)

            case .previousTapped:
                guard case .ready(let items, let index) = state.phase, index > 0 else { return .none }
                let previous = state.current
                state.phase = .ready(items: items, index: index - 1)
                move(to: index - 1, from: previous, in: &state)
                return .none

            case .nextTapped:
                guard case .ready(let items, let index) = state.phase,
                      index + 1 < items.count
                else { return .none }
                let previous = state.current
                state.phase = .ready(items: items, index: index + 1)
                move(to: index + 1, from: previous, in: &state)
                return .none

            case .fullscreenToggled:
                state.isFullscreen.toggle()
                return .none

            case .overlaySelected(let layer):
                // 켤 수 없는 상태에서 눌러도 바뀌지 않는다. 바뀐 것처럼
                // 보이고 아무것도 안 그려지면 **고장으로 읽힌다.**
                guard layer == .off || state.canSelectOverlay else { return .none }
                guard state.overlay != layer else { return .none }
                state.overlay = layer
                return .send(.delegate(.overlayChanged(layer)))

            case .overlayRetryTapped:
                guard case .failed = state.overlayPhase, let item = state.current else {
                    return .none
                }
                state.overlayPhase = .baking
                return .send(
                    .delegate(.overlayRetryRequested(fileName: item.fileName, side: state.side))
                )

            case .overlayPhaseChanged(let phase):
                state.overlayPhase = phase
                // 그릴 수 없게 됐으면 **끈다.** 켜진 채로 두면 아무것도
                // 안 그려지는 화면에서 세그먼트만 "스켈레톤"을 가리킨다.
                if phase != .ready, state.overlay.needsSidecar {
                    state.overlay = .off
                }
                return .none

            case .timeObserved(let seconds):
                state.currentSeconds = seconds
                return .none

            case .reachedEnd:
                // 구간 반복. 스윙 하나가 1~2초이므로 멈추면 매번 다시
                // 눌러야 한다 — 선택지 3.
                guard let scrubber = state.scrubber else { return .none }
                return seek(to: scrubber.start, in: &state)

            case .slowMotionUnsupported(let unsupported):
                state.slowMotionUnsupported = unsupported
                if unsupported { state.speed = .normal }
                return .none

            case .closeTapped:
                state.isPlaying = false
                state.isFullscreen = false
                return .send(.delegate(.closed))

            case .delegate:
                return .none
            }
        }
    }

    /// 칸이 바뀌었다. 구간 시작으로 가고, **클립이 달라졌을 때만** 파일을
    /// 다시 찾는다.
    ///
    /// 같은 클립 안의 다음 스윙이면 `seek`만 한다 — 아이템을 갈면 재생이
    /// 한 번 끊긴다(선택지 1). 그래서 `slowMotionUnsupported`도 그대로
    /// 둔다. 같은 아이템에 대해 플레이어가 다시 보고하지 않기 때문이다.
    ///
    /// **기본 재생 위치는 임팩트가 아니라 구간 시작이다.** IA-FLOW 10.8이
    /// 임팩트를 택한 근거는 "지표가 그 프레임에서 계산되기 때문"인데 그
    /// 지표가 아직 없다 — 영상만 보는 동안에는 처음부터 본다.
    private func move(to index: Int, from previous: ReplayItem?, in state: inout State) {
        guard case .ready(let items, _) = state.phase,
              items.indices.contains(index)
        else { return }
        let item = items[index]
        if item.clipID != previous?.clipID {
            state.clipURL = locator.url(for: item.fileName)
            state.slowMotionUnsupported = false
        }
        state.currentSeconds = item.swing.startSeconds
        state.seek.tick += 1
        state.seek.seconds = item.swing.startSeconds
        // 파일이 없는 칸으로 들어가면 재생은 멈춘다. 넘기기는 살아 있다.
        if state.clipURL == nil { state.isPlaying = false }
    }

    private func seek(to seconds: TimeInterval, in state: inout State) -> Effect<Action> {
        state.currentSeconds = seconds
        state.seek.tick += 1
        state.seek.seconds = seconds
        return .none
    }
}
