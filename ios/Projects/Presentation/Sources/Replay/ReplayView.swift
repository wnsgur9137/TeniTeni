import AVFoundation
import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

/// 세로 리플레이. **클립이 가로**이므로 영상은 레터박스로 들어간다.
///
/// 아래에 남는 자리는 1-D 피드백 카드가 들어갈 곳이다 — 지금 채우지 않는다
/// (docs/07-기획/SPEC-0123-swing-replay.md).
struct ReplayView: View {
    @Bindable var store: StoreOf<ReplayFeature>
    let layer: AVPlayerLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            video
            if let scrubber = store.scrubber {
                ReplayScrubberView(
                    scrubber: scrubber,
                    currentSeconds: store.currentSeconds,
                    onImpact: { store.send(.impactTapped) },
                    onScrub: { store.send(.scrubbed($0)) }
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            speedRow
            transportRow
            swingRow
            feedbackPlaceholder
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { store.send(.closeTapped) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Token.Text.primary)
            }
            .accessibilityLabel("닫기")

            VStack(alignment: .leading, spacing: 2) {
                Text(ReplayView.positionText(store.current))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Token.Text.primary)
                if let item = store.current {
                    Text("\(item.clipFPS)fps")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Token.Text.tertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var video: some View {
        ZStack {
            if store.isClipMissing {
                MissingClipView(fileName: store.current?.fileName ?? "")
            } else {
                PlayerLayerView(layer: layer)
                    .onTapGesture { store.send(.fullscreenToggled) }
                    .overlay(alignment: .bottomTrailing) {
                        Label("탭하면 전체화면", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Token.Text.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Token.Background.scrim, in: .rect(cornerRadius: 6))
                            .padding(10)
                    }
            }
        }
        .frame(height: 219)
        .frame(maxWidth: .infinity)
        .background(.black)
    }

    private var speedRow: some View {
        HStack(spacing: 6) {
            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Button { store.send(.speedSelected(speed)) } label: {
                    Text(speed.label)
                        .font(.system(size: 13, weight: speed == store.effectiveSpeed ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            speed == store.effectiveSpeed ? Token.Text.onAccent : Token.Text.secondary
                        )
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            speed == store.effectiveSpeed ? Token.Accent.primary : Token.Background.surface,
                            in: .rect(cornerRadius: 9)
                        )
                }
                .disabled(store.slowMotionUnsupported && speed != .normal)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .overlay(alignment: .bottom) {
            if store.slowMotionUnsupported {
                Text("이 클립은 느리게 재생할 수 없습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(Token.State.warning)
                    .offset(y: 16)
            }
        }
    }

    private var transportRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Button { store.send(.stepTapped(-1)) } label: {
                    Image(systemName: "backward.frame")
                        .font(.system(size: 16))
                        .foregroundStyle(Token.Text.primary)
                }
                .accessibilityLabel("한 프레임 뒤로")
                Text("프레임")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Token.Text.secondary)
                Button { store.send(.stepTapped(1)) } label: {
                    Image(systemName: "forward.frame")
                        .font(.system(size: 16))
                        .foregroundStyle(Token.Text.primary)
                }
                .accessibilityLabel("한 프레임 앞으로")
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Token.Background.surface, in: .rect(cornerRadius: 11))

            Button { store.send(.playPauseTapped) } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Token.Text.onAccent)
                    .frame(width: 46, height: 46)
                    .background(Token.Accent.primary, in: .circle)
            }
            .accessibilityLabel(store.isPlaying ? "일시정지" : "재생")
            .disabled(store.isClipMissing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var swingRow: some View {
        HStack(spacing: 10) {
            Button { store.send(.previousTapped) } label: {
                Label("이전 스윙", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(store.canGoPrevious ? Token.Text.primary : Token.Text.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Token.Background.surface, in: .rect(cornerRadius: 11))
            }
            .disabled(!store.canGoPrevious)

            Button { store.send(.nextTapped) } label: {
                HStack(spacing: 7) {
                    Text("다음 스윙")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(store.canGoNext ? Token.Text.primary : Token.Text.tertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Token.Background.surface, in: .rect(cornerRadius: 11))
            }
            .disabled(!store.canGoNext)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    /// 1-D 피드백이 들어올 자리. 비어 있다는 것을 숨기지 않는다 —
    /// 빈 카드를 그리면 "데이터가 없다"가 "분석이 실패했다"로 읽힌다.
    private var feedbackPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Token.Background.elevated, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Text("피드백 · 1-D 이후")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Token.Background.elevated)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
    }

    static func positionText(_ item: ReplayItem?) -> String {
        guard let item else { return "스윙" }
        return "스윙 \(item.position) / \(item.total)"
    }
}

/// 영상 파일이 없을 때의 자리. **이 스윙을 건너뛰지 않는다** — 건너뛰면
/// "34개 중 12번째"의 분모가 달라져 사용자가 세던 수와 어긋난다.
struct MissingClipView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 30))
                .foregroundStyle(Token.State.warning)
            Text("이 클립의 영상 파일이 없습니다")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Token.Text.primary)
            Text(fileName)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Token.Background.surface)
        .accessibilityElement(children: .combine)
    }
}
