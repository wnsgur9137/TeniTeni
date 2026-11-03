import ComposableArchitecture
import DesignSystem
import SwiftUI
import TeniVision

/// 리플레이의 바깥 껍데기. **플레이어와 방향 잠금을 소유한다.**
///
/// `CaptureScreen`과 같은 구조다 — 리듀서는 선언적 상태만 들고 있고, 그
/// 상태를 `AVPlayer` 명령으로 옮기는 일은 여기서 한다. 세로/가로가 바뀌어도
/// `ReplayPlayer`는 그대로이므로 재생 위치와 배속이 유지된다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 7·8
public struct ReplayScreen: View {

    @Bindable private var store: StoreOf<ReplayFeature>
    @State private var player = ReplayPlayer()
    /// 사이드카를 들고 있는 쪽. 플레이어와 같은 이유로 **화면이 소유한다** —
    /// 프레임 수백 개를 리듀서 상태에 두지 않는다.
    @State private var overlay: ReplayOverlaySource

    public init(store: StoreOf<ReplayFeature>, overlayQueue: OverlayBakeQueue) {
        self.store = store
        self._overlay = State(initialValue: ReplayOverlaySource(queue: overlayQueue))
    }

    public var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()

            switch store.phase {
            case .loading:
                ProgressView().tint(Token.Accent.primary)

            case .failed(let reason):
                failure(reason)

            case .ready:
                if store.isFullscreen {
                    ReplayFullscreenView(store: store, layer: player.layer, overlay: overlay)
                } else {
                    ReplayView(store: store, layer: player.layer)
                }
            }
        }
        .task {
            player.onTime = { [store] seconds in store.send(.timeObserved(seconds)) }
            player.onReachedEnd = { [store] in store.send(.reachedEnd) }
            player.onSlowMotionSupport = { [store] supported in
                store.send(.slowMotionUnsupported(!supported))
            }
            overlay.onPhase = { [store] phase in store.send(.overlayPhaseChanged(phase)) }
            store.send(.appeared)
        }
        // 선언적 상태 → 플레이어 명령. 아래 네 개가 이 화면의 전체 배선이다.
        .onChange(of: store.clipURL) { _, url in
            guard let url else {
                player.unload()
                return
            }
            player.load(url: url, startAt: store.currentSeconds)
            applySegment()
        }
        // 클립이 바뀌면 사이드카도 바뀐다. **파일 이름으로 본다** — 같은
        // 클립 안의 다음 스윙에서는 다시 읽지 않는다.
        //
        // 사이드카가 없으면 소스가 큐에 넣는다. **보관함에서 연 세션이
        // 여기로 온다** — 촬영 종료만으로 넣으면 어제 찍은 세션은 영원히
        // "분석 전"이고 탈출구가 없다.
        .onChange(of: ClipIdentity(store)) { _, identity in
            overlay.load(fileName: identity.fileName, side: identity.side)
        }
        // 다시 시도. 큐 투입과 감시를 소스가 한 Task에서 한다.
        .onChange(of: store.overlayPhase) { previous, phase in
            if phase == .baking, previous != .baking {
                overlay.retry()
            }
        }
        .onChange(of: store.seek) { _, command in
            Task { await player.seek(to: command.seconds) }
            applySegment()
        }
        .onChange(of: store.step) { _, command in
            player.step(by: command.count)
        }
        .onChange(of: PlaybackState(store)) { _, state in
            player.apply(speed: state.speed, playing: state.isPlaying)
        }
        // 전체화면은 방향을 바꾼다. **나올 때 반드시 푼다** — 풀지 않으면
        // 요약과 보관함이 가로로 남는다.
        .onChange(of: store.isFullscreen) { _, fullscreen in
            if fullscreen {
                OrientationLock.shared.lock(to: [.landscapeLeft, .landscapeRight])
            } else {
                OrientationLock.shared.release()
            }
        }
        // **지울 것을 적어서 보여준다.** 되돌리기가 없으므로 이것이 유일한
        // 안전장치다(SPEC-0126 선택지 3).
        .confirmationDialog(
            store.deleting?.title ?? "",
            isPresented: Binding(
                get: { store.deleting != nil },
                set: { if !$0 { store.send(.deleteCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: store.deleting
        ) { _ in
            Button("지우기", role: .destructive) { store.send(.deleteConfirmed) }
            Button("취소", role: .cancel) { store.send(.deleteCancelled) }
        } message: { target in
            Text("\(target.detail)\n\(target.counts)\n\(target.warning)")
        }
        .alert(
            "지우지 못했습니다",
            isPresented: Binding(
                get: { store.deleteFailure != nil },
                set: { if !$0 { store.send(.deleteFailureDismissed) } }
            )
        ) {
            Button("확인") { store.send(.deleteFailureDismissed) }
        } message: {
            Text(store.deleteFailure ?? "")
        }
        .onDisappear {
            player.unload()
            OrientationLock.shared.release()
        }
    }

    private func applySegment() {
        guard let scrubber = store.scrubber else { return }
        player.setSegment(end: scrubber.end)
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Token.State.warning)
            Text(reason)
                .font(.system(size: 17))
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("다시 시도") { store.send(.retryTapped) }
                    .buttonStyle(.borderedProminent)
                    .tint(Token.Accent.primary)
                Button("닫기") { store.send(.closeTapped) }
                    .tint(Token.Text.secondary)
            }
        }
        .padding(28)
    }
}

/// 클립 파일과 라켓 쪽. 둘을 함께 본다 — 손잡이는 바뀌지 않지만 소스가
/// 굽기를 걸 때 필요하고, 따로 관측하면 파일만 바뀐 전이에서 옛 손을 쓴다.
private struct ClipIdentity: Equatable {
    let fileName: String?
    let side: RacketSide

    @MainActor
    init(_ store: StoreOf<ReplayFeature>) {
        self.fileName = store.current?.fileName
        self.side = store.side
    }
}

/// 배속과 재생 여부를 **한 번에** 본다. 따로 관측하면 배속을 바꿀 때
/// `rate`가 두 번 설정되고, 그 사이에 한 틱이 1×로 재생된다.
private struct PlaybackState: Equatable {
    let speed: PlaybackSpeed
    let isPlaying: Bool

    /// `Store`를 읽는 것은 메인 액터의 일이다. 표시하지 않으면 전체 빌드에서
    /// 경고가 난다 — 증분 빌드는 그것을 숨긴다.
    @MainActor
    init(_ store: StoreOf<ReplayFeature>) {
        self.speed = store.effectiveSpeed
        self.isPlaying = store.isPlaying
    }
}
