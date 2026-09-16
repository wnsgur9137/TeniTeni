import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

public struct HomeView: View {
    @Bindable private var store: StoreOf<HomeFeature>

    public init(store: StoreOf<HomeFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 9) {
                        ForEach(CaptureSituation.allCases, id: \.self) { card($0) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                footer
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("오늘은 어떻게 치나요")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Token.Text.primary)
                Text("상황에 따라 유효한 피드백이 달라집니다")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Text.secondary)
            }
            Spacer()
            Button { store.send(.settingsTapped) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Token.Text.secondary)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private func card(_ situation: CaptureSituation) -> some View {
        let selected = store.situation == situation
        return Button { store.send(.situationSelected(situation)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Text(situation.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Token.Text.primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(selected ? Token.Accent.primary : Token.Text.tertiary)
                }

                if selected, situation.allowsLineCall {
                    observablePicker
                }

                Label(
                    store.effectiveObservable.placement,
                    systemImage: "mappin.and.ellipse"
                )
                .font(.system(size: 12))
                .foregroundStyle(Token.Text.secondary)

                if !situation.disabledRules.isEmpty {
                    Text("팔로스루 피드백은 제외됩니다 — 벽이 가까워 구조적으로 짧습니다")
                        .font(.system(size: 11))
                        .foregroundStyle(Token.State.warning)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Token.Background.surface, in: .rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        selected ? Token.Accent.primary : Token.Background.elevated,
                        lineWidth: selected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    /// 시합에서만 나타난다. 다른 상황에는 판정할 라인이 없다.
    private var observablePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("무엇을 볼까요")
                .font(.system(size: 11))
                .foregroundStyle(Token.Text.tertiary)
            HStack(spacing: 8) {
                ForEach(ObservationTarget.allCases, id: \.self) { target in
                    let on = store.observable == target
                    Button { store.send(.observableSelected(target)) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(on ? Token.Accent.primary : Token.Text.tertiary)
                            Text(target.label)
                                .font(.system(size: 13, weight: on ? .medium : .regular))
                                .foregroundStyle(on ? Token.Text.primary : Token.Text.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Token.Background.surface, in: .rect(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(
                                    on ? Token.Accent.primary : Token.Background.elevated,
                                    lineWidth: on ? 1.5 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if store.observable == .lineCall {
                Text("라인 판정을 고르면 폰을 판정할 라인의 연장선으로 옮겨야 합니다")
                    .font(.system(size: 11))
                    .foregroundStyle(Token.State.warning)
            }
        }
        .padding(11)
        .background(Token.Background.elevated, in: .rect(cornerRadius: 9))
    }

    private var footer: some View {
        Button { store.send(.startTapped) } label: {
            Text("시작")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Token.Text.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
