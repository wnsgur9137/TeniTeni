import DesignSystem
import SwiftUI

/// 페이즈 스크러버. **3점만 말한다** — 구간 시작 · 임팩트 · 끝.
///
/// 5구간(준비·테이크백·포워드·임팩트·팔로스루)을 그리지 않는 이유: `Swing`이
/// 가진 것은 세 점이고, 비율로 나누면 **그럴듯하지만 거짓인 눈금**이 생긴다.
/// 사용자가 "테이크백이 짧다"를 그 눈금으로 읽으면 우리가 정한 비율을 읽는
/// 것이다. 5페이즈는 1-D가 경계를 만든 뒤에 올린다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md
struct ReplayScrubberView: View {
    let scrubber: ReplayScrubber
    let currentSeconds: TimeInterval
    let onImpact: () -> Void
    let onScrub: (Double) -> Void

    private var progress: Double { scrubber.fraction(at: currentSeconds) }

    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Token.Background.elevated).frame(height: 6)
                    Capsule()
                        .fill(Token.Text.tertiary)
                        .frame(width: width * progress, height: 6)
                    // 임팩트 마커. 탭 타깃을 44pt로 넓히되 그림은 2pt 선이다.
                    Rectangle()
                        .fill(Token.Accent.primary)
                        .frame(width: 2, height: 28)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .offset(x: width * scrubber.impactFraction - 22)
                        .onTapGesture { onImpact() }
                        .accessibilityLabel("임팩트로 이동")
                    Circle()
                        .fill(Token.Accent.primary)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Token.Background.base, lineWidth: 3))
                        .offset(x: width * progress - 8)
                        .allowsHitTesting(false)
                }
                .frame(height: 44)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard width > 0 else { return }
                            onScrub(value.location.x / width)
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text(Self.time(0))
                Spacer()
                Text("임팩트 \(Self.time(scrubber.impact - scrubber.start))")
                    .foregroundStyle(Token.Accent.primary)
                    .fontWeight(.bold)
                Spacer()
                Text(Self.time(scrubber.duration))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Token.Text.tertiary)
        }
    }

    static func time(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", max(seconds, 0))
    }
}
