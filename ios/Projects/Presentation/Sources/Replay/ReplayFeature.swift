import ComposableArchitecture
import Domain
import Foundation

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

        /// 플레이어가 올려보내는 것
        case timeObserved(TimeInterval)
        case reachedEnd
        case slowMotionUnsupported(Bool)

        case delegate(Delegate)

        public enum Delegate: Equatable {
            case closed
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
