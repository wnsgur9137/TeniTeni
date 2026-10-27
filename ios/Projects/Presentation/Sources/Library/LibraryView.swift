import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

/// 보관함 — 과거 세션 목록.
///
/// **유형 필터와 썸네일 그리드를 만들지 않는다.** 목업에 있었지만 둘 다
/// 1-D 분류가 생긴 뒤의 것이다 — 지금은 필터할 축도, 보여줄 점수도 없다
/// (SPEC-0116).
///
/// 목업: docs/06-디자인/_canvas/Library.dc.html · LibraryEmpty.dc.html
public struct LibraryView: View {
    @Bindable private var store: StoreOf<LibraryFeature>

    public init(store: StoreOf<LibraryFeature>) {
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

            case .loaded(let sessions):
                if sessions.isEmpty {
                    empty
                } else {
                    list(sessions)
                }
            }
        }
        // 탭이 처음 뜰 때 읽는다. 탭으로 **되돌아올** 때는 이 뷰가 살아
        // 있어 다시 돌지 않으므로, `AppFeature`가 탭 선택에서 한 번 더
        // 보낸다 — 둘 다 필요하다.
        .task { store.send(.appeared) }
    }

    // MARK: 목록

    private func list(_ sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(count: sessions.count)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(sessions) { session in
                        Button { store.send(.sessionTapped(session.id)) } label: {
                            row(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Token.Background.surface, in: .rect(cornerRadius: 13))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("보관함")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Token.Text.primary)
            Text("세션 \(count)개")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func row(_ session: Session) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.rowDate(session.startedAt))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Token.Text.primary)
                Text(Self.subtitle(session))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Token.Text.tertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.swingCount)")
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    // 0개 세션도 목록에 남는다 — 영상은 있다(SPEC-0110).
                    // 눌러도 되지만 **기대를 낮춰** 보여준다.
                    .foregroundStyle(
                        session.swingCount == 0 ? Token.Text.tertiary : Token.Text.primary
                    )
                Text("스윙")
                    .font(.system(size: 10))
                    .foregroundStyle(Token.Text.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Token.Text.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Self.rowDate(session.startedAt)), \(Self.subtitle(session)), 스윙 \(session.swingCount)개"
        )
    }

    // MARK: 비어 있음

    /// "없다"만 말하고 끝내면 사용자는 다음에 무엇을 할지 모른다.
    private var empty: some View {
        VStack(spacing: 0) {
            header(count: 0)
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "square.stack")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Token.Background.elevated)
                Text("아직 찍은 것이\n없습니다")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Token.Text.primary)
                    .multilineTextAlignment(.center)
                Text("코트에서 한 번 찍으면\n여기에 쌓입니다.")
                    .font(.system(size: 14))
                    .foregroundStyle(Token.Text.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                Button { store.send(.captureTapped) } label: {
                    Text("촬영하러 가기")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Token.Text.onAccent)
                        .padding(.horizontal, 28)
                        .frame(minHeight: 50)
                        .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    // MARK: 실패

    /// **빈 목록으로 위장하지 않는다.** 사용자는 찍은 것이 사라졌다고 읽는다.
    private func failure(_ reason: String) -> some View {
        VStack(spacing: 0) {
            header(count: 0)
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 38))
                    .foregroundStyle(Token.State.warning)
                Text(reason)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Token.Text.primary)
                    .multilineTextAlignment(.center)
                // 이 한 줄이 "없다"와 "읽지 못했다"를 가른다.
                Text("찍은 영상이 지워진 것은 아닙니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Text.tertiary)
                    .multilineTextAlignment(.center)
                Button { store.send(.retryTapped) } label: {
                    Text("다시 시도")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Token.Text.onAccent)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 48)
                        .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    // MARK: 포매팅

    private static let rowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 · HH:mm"
        return formatter
    }()

    static func rowDate(_ date: Date) -> String { rowFormatter.string(from: date) }

    /// 상황 · 관찰 대상 · 클립 수 · fps.
    ///
    /// **fps를 줄마다 적는다.** 발열로 강등되면 세션마다 다르고, 그 사실이
    /// 드러나는 자리가 여기와 요약뿐이다(ADR-0005).
    static func subtitle(_ session: Session) -> String {
        [
            session.situation.label,
            session.observable.label,
            "클립 \(session.clips.count)개",
            "\(session.fps)fps",
        ].joined(separator: " · ")
    }
}
