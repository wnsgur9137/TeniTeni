import AVFoundation
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI
import TeniVision

/// 가로 전체화면. 영상을 탭했을 때.
///
/// **같은 `AVPlayer`를 쓴다** — 아이템을 갈지 않으므로 재생 위치와 배속이
/// 유지된다. 바뀌는 것은 레이어 프레임과 컨트롤 배치뿐이다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 8.
struct ReplayFullscreenView: View {
    @Bindable var store: StoreOf<ReplayFeature>
    let layer: AVPlayerLayer
    /// 사이드카를 들고 있는 쪽. `nil`이면 오버레이를 그리지 않는다.
    var overlay: ReplayOverlaySource?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(layer: layer)
                .ignoresSafeArea()
                .onTapGesture { store.send(.fullscreenToggled) }

            if store.canDrawOverlay, let overlay, let sidecar = overlay.sidecar {
                ReplayOverlayCanvas(
                    layer: store.overlay,
                    frame: overlay.frame(at: store.currentSeconds),
                    trail: store.overlay == .racket
                        ? overlay.racketTrail(until: store.currentSeconds, trail: Self.trailSeconds)
                        : [],
                    pixelSize: CGSize(width: sidecar.pixelWidth, height: sidecar.pixelHeight),
                    side: store.side
                )
                .ignoresSafeArea()
            }

            if store.overlay == .racket, store.canDrawOverlay {
                estimateBadge
            }

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

    /// 라켓 궤적에서 **뒤로 보여주는 구간**. 스윙 하나가 1~2초이므로
    /// 0.6초면 테이크백에서 임팩트까지가 들어온다. 전부 그리면 궤적이
    /// 스스로 겹쳐 무엇이 지금인지 알 수 없다.
    private static let trailSeconds: TimeInterval = 0.6

    /// **측정값이 아니라고 화면에서 말한다.** 사용자가 측정으로 읽으면
    /// 틀린 숫자를 믿게 되고, 한 번 잃은 신뢰는 돌아오지 않는다.
    private var estimateBadge: some View {
        VStack {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("추정 — 라켓은 영상에서 보이지 않습니다")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Token.Overlay.racketTrail)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Token.Background.scrim, in: .rect(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Token.Overlay.racketTrail.opacity(0.42), lineWidth: 1)
                )
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// 오버레이 모드 전환. **이 화면에만 있다.**
    ///
    /// 세로는 영상이 219pt여서 사람이 약 88pt다 — 관절 19개가 읽히지 않는다.
    /// 읽히지 않는 것을 켜는 스위치는 자리만 차지한다 (SPEC-0121 선택지 3).
    private var overlaySegment: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(OverlayLayer.allCases, id: \.self) { layer in
                    let selected = layer == store.overlay
                    let enabled = layer == .off || store.canSelectOverlay
                    Button { store.send(.overlaySelected(layer)) } label: {
                        Text(layer.title)
                            .font(.system(size: 12, weight: selected ? .bold : .semibold))
                            .foregroundStyle(
                                selected
                                    ? Token.Text.onAccent
                                    : (enabled ? Token.Text.secondary : Token.Text.tertiary)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                selected ? Token.Overlay.racketArm : .clear,
                                in: .rect(cornerRadius: 7)
                            )
                    }
                    .disabled(!enabled)
                }
            }
            .padding(3)
            .frame(width: 258)
            .background(Token.Background.elevated, in: .rect(cornerRadius: 9))

            if let notice = store.overlayNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Token.Text.tertiary)
                    .lineLimit(1)
            }

            if case .failed = store.overlayPhase {
                Button("다시 시도") { store.send(.overlayRetryTapped) }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Token.Text.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Token.Background.elevated, in: .rect(cornerRadius: 7))
            }

            Spacer()
        }
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

            overlaySegment
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [.clear, Token.Background.scrim],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
