import DesignSystem
import SwiftUI

/// 촬영 시작 직전 한 화면. **카메라가 제대로 잡혔는지 여기서 확인한다.**
///
/// 레퍼런스의 반복되는 불만이 이 지점이다 — 코트에 나가면 화면을 볼 수 없어
/// 구도가 맞는지 모른다(docs/08-레퍼런스/SwingVision.md).
///
/// 프리뷰는 `CaptureScreen`이 뒤에 깔아 둔다. 이 뷰는 그 위에 얹는 것만 그린다.
///
/// 목업: docs/06-디자인/_canvas/FramingGuide.dc.html
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.6
struct FramingGuideView: View {

    let guidance: FramingGuidance
    let subject: String
    /// 프리뷰가 있어야 구도를 맞출 수 있다. 없으면 가이드도 시작도 의미가 없다.
    let canStart: Bool
    let onStart: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            if canStart { guideFrame }

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
    private var guideFrame: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = frameRect(in: size)

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    Token.Accent.primary,
                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            if guidance.frame == .body {
                // 측정 브래킷과 비율 라벨은 **프레임 왼쪽 모서리에** 붙는다.
                // 좌표를 프레임에서 뽑아 쓴다 — 화면 비율이 바뀌어도 따라간다.
                heightBracket(for: rect)
                ratioTag(for: rect)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 내 스윙: 프레임 높이의 38%(5.1절 권장 6m 배치에서 선수가 차지하는 비율).
    /// 라인 판정: 화면을 가로지르는 띠.
    private func frameRect(in size: CGSize) -> CGRect {
        switch guidance.frame {
        case .body:
            let height = size.height * 0.38
            let width = height * 0.9
            return CGRect(
                x: (size.width - width) / 2,
                y: size.height * 0.64 - height / 2,
                width: width,
                height: height
            )
        case .line:
            let width = size.width * 0.9
            let height = size.height * 0.18
            return CGRect(
                x: (size.width - width) / 2,
                y: size.height * 0.62 - height / 2,
                width: width,
                height: height
            )
        }
    }

    private func heightBracket(for rect: CGRect) -> some View {
        Path { path in
            let x = rect.minX - 16
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: x - 6, y: rect.minY))
            path.addLine(to: CGPoint(x: x + 6, y: rect.minY))
            path.move(to: CGPoint(x: x - 6, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + 6, y: rect.maxY))
        }
        .stroke(Token.Accent.primary, lineWidth: 1.5)
    }

    private func ratioTag(for rect: CGRect) -> some View {
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
        .fixedSize()
        .position(x: rect.minX - 72, y: rect.midY)
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

            // 프리뷰가 없으면 촬영에 들어가봐야 닫기밖에 없는 화면이다.
            Button(action: onStart) {
                Text("촬영 시작")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canStart ? Token.Text.onAccent : Token.Text.tertiary)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 46)
                    .background(
                        canStart ? Token.Accent.primary : Token.Background.surface,
                        in: .rect(cornerRadius: 9)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canStart)
        }
    }
}
