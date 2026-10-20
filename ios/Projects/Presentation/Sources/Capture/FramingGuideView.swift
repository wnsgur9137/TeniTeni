import DesignSystem
import SwiftUI

/// 촬영 시작 직전 한 화면. **카메라가 제대로 잡혔는지 여기서 확인한다.**
///
/// 레퍼런스의 반복되는 불만이 이 지점이다 — 코트에 나가면 화면을 볼 수 없어
/// 구도가 맞는지 모른다(docs/08-레퍼런스/SwingVision.md).
///
/// 목업: docs/06-디자인/_canvas/FramingGuide.dc.html
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.6
struct FramingGuideView: View {

    let guidance: FramingGuidance
    let subject: String
    let controller: CameraController
    let onStart: () -> Void
    let onBack: () -> Void

    private var hasPreview: Bool {
        controller.status == .ready || controller.status == .recording
    }

    var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()

            if hasPreview {
                CameraPreview(session: controller.session).ignoresSafeArea()
                guideFrame
            } else {
                CapturePlaceholder(status: controller.status)
            }

            VStack {
                headline
                Spacer()
                HStack(alignment: .bottom) {
                    subjectCard
                    Spacer()
                    actions
                }
            }
            .padding(20)
        }
    }

    // MARK: 구도 가이드

    /// 관찰 대상에 따라 모양이 다르다. 내 스윙은 선수를, 라인 판정은 라인을 담는다.
    @ViewBuilder
    private var guideFrame: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch guidance.frame {
            case .body:
                // 프레임 높이의 38% — 5.1절 권장 6m 배치에서 선수가 차지하는 비율
                let height = size.height * 0.38
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Token.Accent.primary,
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                    .frame(width: height * 0.9, height: height)
                    .position(x: size.width / 2, y: size.height * 0.64)
                    .overlay(alignment: .topLeading) { ratioTag(size: size) }
            case .line:
                // 라인은 화면을 가로지른다. 좌우 여유를 남긴다
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Token.Accent.primary,
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                    .frame(width: size.width * 0.9, height: size.height * 0.18)
                    .position(x: size.width / 2, y: size.height * 0.62)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ratioTag(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("35~45%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Token.Accent.primary)
            Text("선수 높이")
                .font(.system(size: 11))
                .foregroundStyle(Token.Text.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Token.Background.scrim, in: .rect(cornerRadius: 7))
        .position(x: size.width * 0.22, y: size.height * 0.6)
    }

    // MARK: 안내

    private var headline: some View {
        VStack(spacing: 3) {
            Text(guidance.headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Token.Text.primary)
            Text(guidance.placement)
                .font(.system(size: 12))
                .foregroundStyle(Token.Text.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Token.Background.scrim, in: .rect(cornerRadius: 10))
    }

    private var subjectCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("이번 촬영")
                .font(.system(size: 11))
                .foregroundStyle(Token.Text.tertiary)
            Text(subject)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Token.Text.primary)
            Text("잘못 골랐으면 뒤로 — 삼각대를 옮기기 전에")
                .font(.system(size: 11))
                .foregroundStyle(Token.Text.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Token.Background.scrim, in: .rect(cornerRadius: 9))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Text("뒤로")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Token.Text.secondary)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 46)
                    .background(Token.Background.surface, in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Token.Background.elevated, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                Text("촬영 시작")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Token.Text.onAccent)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 46)
                    .background(Token.Accent.primary, in: .rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
    }
}
