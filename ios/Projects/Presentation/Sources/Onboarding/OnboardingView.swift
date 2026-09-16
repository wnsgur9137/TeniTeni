import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct OnboardingView: View {
    @Bindable private var store: StoreOf<OnboardingFeature>

    public init(store: StoreOf<OnboardingFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()
            VStack(spacing: 0) {
                steps
                switch store.step {
                case .intro: intro
                case .handedness: handedness
                }
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingFeature.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= store.step.rawValue
                          ? Token.Accent.primary : Token.Background.elevated)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 40)
            Text("TENITENI")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Token.Accent.primary)
            Text("스윙을 보고\n무엇을 고칠지 안다")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Token.Text.primary)
                .padding(.top, 10)

            guide(
                title: "삼각대에 세워두세요",
                body: "코트 옆 6m, 허리 높이, 가로로.\n흔들리면 공 궤적을 잡지 못합니다."
            )
            .padding(.top, 34)
            guide(
                title: "치기만 하면 됩니다",
                body: "스윙을 자동으로 찾아 기록합니다.\n폰을 보러 올 필요 없습니다."
            )
            .padding(.top, 20)

            Spacer()
            Button { store.send(.startTapped) } label: {
                Text("시작하기")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.Text.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
            }
            Text("카메라와 마이크 권한이 필요합니다")
                .font(.system(size: 12))
                .foregroundStyle(Token.Text.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 34)
        }
        .padding(.horizontal, 24)
    }

    private func guide(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Token.Text.primary)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Token.Text.secondary)
                .lineSpacing(3)
        }
    }

    private var handedness: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 34)
            Text("어느 손으로\n라켓을 잡나요")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Token.Text.primary)
            Text("스켈레톤에서 라켓 잡은 팔을 강조하고,\n포핸드와 백핸드를 가르는 기준이 됩니다.")
                .font(.system(size: 14))
                .foregroundStyle(Token.Text.secondary)
                .lineSpacing(3)
                .padding(.top, 10)

            HStack(spacing: 12) {
                ForEach(Handedness.allCases, id: \.self) { hand in
                    handCard(hand)
                }
            }
            .padding(.top, 34)

            Text("나중에 설정 → 프로필에서 바꿀 수 있습니다. 바꾸면 이전 기록의 포핸드·백핸드 표기도 함께 달라집니다.")
                .font(.system(size: 13))
                .foregroundStyle(Token.Text.secondary)
                .lineSpacing(3)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Token.Background.surface, in: .rect(cornerRadius: 12))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Token.Text.tertiary).frame(width: 3)
                }
                .padding(.top, 26)

            Spacer()
            Button { store.send(.finishTapped) } label: {
                Text("다음")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.Text.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        store.handedness == nil ? Token.Background.elevated : Token.Accent.primary,
                        in: .rect(cornerRadius: 10)
                    )
            }
            .disabled(store.handedness == nil)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 24)
    }

    private func handCard(_ hand: Handedness) -> some View {
        let selected = store.handedness == hand
        return Button { store.send(.handednessSelected(hand)) } label: {
            VStack(spacing: 14) {
                Image(systemName: hand == .right ? "figure.tennis" : "figure.tennis")
                    .font(.system(size: 44))
                    .foregroundStyle(selected ? Token.Overlay.racketArm : Token.Text.tertiary)
                    .scaleEffect(x: hand == .left ? -1 : 1)
                Text(hand.label)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Token.Text.primary : Token.Text.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Token.Background.surface, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        selected ? Token.Accent.primary : Token.Background.elevated,
                        lineWidth: selected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
