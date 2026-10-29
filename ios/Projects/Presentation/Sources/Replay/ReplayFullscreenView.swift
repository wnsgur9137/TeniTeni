import AVFoundation
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// 가로 전체화면. 영상을 탭했을 때.
///
/// **같은 `AVPlayer`를 쓴다** — 아이템을 갈지 않으므로 재생 위치와 배속이
/// 유지된다. 바뀌는 것은 레이어 프레임과 컨트롤 배치뿐이다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 8.
struct ReplayFullscreenView: View {
    @Bindable var store: StoreOf<ReplayFeature>
    let layer: AVPlayerLayer

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(layer: layer)
                .ignoresSafeArea()
                .onTapGesture { store.send(.fullscreenToggled) }

            VStack(spacing: 0) {
                top
                Spacer()
                controls
            }
        }
    }

    private var top: some View {
        HStack(spacing: 12) {
            Button { store.send(.fullscreenToggled) } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.Text.primary)
            }
            .accessibilityLabel("세로로 돌아가기")

            Text(ReplayView.positionText(store.current))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Token.Text.primary)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Token.Background.scrim, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var controls: some View {
        VStack(spacing: 11) {
            if let scrubber = store.scrubber {
                ReplayScrubberView(
                    scrubber: scrubber,
                    currentSeconds: store.currentSeconds,
                    onImpact: { store.send(.impactTapped) },
                    onScrub: { store.send(.scrubbed($0)) }
                )
            }

            HStack(spacing: 14) {
                Button { store.send(.stepTapped(-1)) } label: {
                    Image(systemName: "backward.frame")
                        .foregroundStyle(Token.Text.primary)
                }
                .accessibilityLabel("한 프레임 뒤로")

                Button { store.send(.playPauseTapped) } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Token.Text.onAccent)
                        .frame(width: 42, height: 42)
                        .background(Token.Accent.primary, in: .circle)
                }
                .accessibilityLabel(store.isPlaying ? "일시정지" : "재생")

                Button { store.send(.stepTapped(1)) } label: {
                    Image(systemName: "forward.frame")
                        .foregroundStyle(Token.Text.primary)
                }
                .accessibilityLabel("한 프레임 앞으로")

                Spacer()

                ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                    Button { store.send(.speedSelected(speed)) } label: {
                        Text(speed.label)
                            .font(.system(size: 11, weight: speed == store.effectiveSpeed ? .bold : .semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                speed == store.effectiveSpeed ? Token.Text.onAccent : Token.Text.secondary
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                speed == store.effectiveSpeed
                                    ? Token.Accent.primary : Token.Background.elevated,
                                in: .rect(cornerRadius: 7)
                            )
                    }
                    .disabled(store.slowMotionUnsupported && speed != .normal)
                }

                Spacer()

                Button { store.send(.previousTapped) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(store.canGoPrevious ? Token.Text.primary : Token.Text.tertiary)
                }
                .disabled(!store.canGoPrevious)
                .accessibilityLabel("이전 스윙")

                Button { store.send(.nextTapped) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(store.canGoNext ? Token.Text.primary : Token.Text.tertiary)
                }
                .disabled(!store.canGoNext)
                .accessibilityLabel("다음 스윙")
            }
            .font(.system(size: 17))
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [.clear, Token.Background.scrim],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
