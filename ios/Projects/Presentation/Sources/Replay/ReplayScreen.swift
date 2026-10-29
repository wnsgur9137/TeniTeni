import ComposableArchitecture
import DesignSystem
import SwiftUI

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

    public init(store: StoreOf<ReplayFeature>) {
        self.store = store
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
                    ReplayFullscreenView(store: store, layer: player.layer)
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
