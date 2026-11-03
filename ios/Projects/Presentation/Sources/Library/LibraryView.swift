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
        // **지울 것을 적어서 보여준다.** 되돌리기가 없으므로 이것이 유일한
        // 안전장치다(SPEC-0126 선택지 3).
        .confirmationDialog(
            store.deleting?.title ?? "",
            isPresented: Binding(
                get: { store.deleting != nil },
                set: { if !$0 { store.send(.deleteCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: store.deleting
        ) { target in
            Button("지우기", role: .destructive) { store.send(.deleteConfirmed) }
            Button("취소", role: .cancel) { store.send(.deleteCancelled) }
        } message: { target in
            // 무엇이 사라지는지 **숫자로** 적는다. "정말 지울까요?"만 묻는
            // 것은 확인이 아니라 절차다.
            Text("\(target.detail)\n\(target.counts)\n\(target.warning)")
        }
        // 조용히 넘기면 사용자는 지워진 줄 안다 — 실제로는 영상만
        // 사라지고 레코드가 남았다.
        .alert(
            "지우지 못했습니다",
            isPresented: Binding(
                get: { store.deleteFailure != nil },
                set: { if !$0 { store.send(.deleteFailureDismissed) } }
            )
        ) {
            Button("확인") { store.send(.deleteFailureDismissed) }
        } message: {
            Text(store.deleteFailure ?? "")
        }
    }

    // MARK: 목록

    private func list(_ sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(count: sessions.count)
            // ★ `ScrollView` + `VStack`에서 `List`로 바꿨다.
            //
            //   `.swipeActions`는 **List에서만** 동작한다. IA-FLOW 10.6이
            //   삭제를 "보관함 스와이프"로 정했고, 파괴적 행 동작의 iOS
            //   관용구가 그것이다 — 접근성(VoiceOver의 행 동작)도 공짜로
            //   따라온다.
            //
            //   ⚠️ **보이는 모양이 바뀐다.** 예전에는 묶음 하나에 둥근
            //   배경이 있었고, 지금은 줄마다 배경이 있다. 스크린샷으로
            //   확인되지 않았다(미수행).
            List {
                ForEach(sessions) { session in
                    Button { store.send(.sessionTapped(session.id)) } label: {
                        row(session)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(
                        Token.Background.surface
                            .clipShape(.rect(cornerRadius: 13))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 1)
                    )
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // `allowsFullSwipe: false` — **끝까지 밀어도 바로
                        // 지워지지 않는다.** 되돌리기가 없으므로 전체
                        // 스와이프로 즉시 삭제되는 것은 너무 싸다.
                        Button(role: .destructive) {
                            store.send(.deleteRequested(session.id))
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.bottom, 24)
        }
    }

    /// `count`가 `nil`이면 수를 적지 않는다.
    ///
    /// 빈 화면·실패 화면에서는 "세션 0개"가 **아래 문구와 겹친다** —
    /// "아직 찍은 것이 없습니다" 위에 "세션 0개"를 또 쓸 이유가 없고,
    /// 읽기 실패에서는 **거짓이다**(0개인지 모른다). 목업도 그 자리를
    /// 비워 뒀다.
    private func header(count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("보관함")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Token.Text.primary)
            if let count {
                Text("세션 \(count)개")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Token.Text.tertiary)
            }
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
                // 결손이 있으면 **그 줄을 대신한다.** 아래에 한 줄 더
                // 붙이면 행 높이가 세션마다 달라져 목록이 들쭉날쭉해진다.
                if let notice = store.availability[session.id]?.notice {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(notice)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Token.State.warning)
                } else {
                    Text(Self.subtitle(session))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Token.Text.tertiary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // ★ **수를 바꾸지 않는다.** 찍은 사실은 지워지지 않았고,
                //   재생 가능한 수로 바꾸면 사용자가 세던 수와 어긋난다
                //   (SPEC-0120 선택지 2). 틀린 것은 "지금 보여줄 수 있다"는
                //   암시이고 그것은 왼쪽 경고가 거둔다.
                Text("\(session.swingCount)")
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    // 0개 세션도 목록에 남는다 — 영상은 있다(SPEC-0110).
                    // 눌러도 되지만 **기대를 낮춰** 보여준다.
                    //
                    // 영상이 전부 없는 세션도 같은 취급이다: 눌리지만
                    // 보여줄 것이 없다는 사실을 미리 말한다.
                    .foregroundStyle(
                        session.swingCount == 0
                            || store.availability[session.id] == ClipAvailability.missing
                            ? Token.Text.tertiary : Token.Text.primary
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
        .accessibilityLabel(Self.rowLabel(session, store.availability[session.id]))
    }

    // MARK: 비어 있음

    /// "없다"만 말하고 끝내면 사용자는 다음에 무엇을 할지 모른다.
    private var empty: some View {
        VStack(spacing: 0) {
            header(count: nil)
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
            header(count: nil)
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
    /// 보이스오버가 읽는 한 줄. **결손을 빠뜨리지 않는다** — 경고 아이콘은
    /// 읽히지 않으므로 여기에 글자로 들어가야 한다.
    static func rowLabel(_ session: Session, _ availability: ClipAvailability?) -> String {
        var parts = [rowDate(session.startedAt)]
        if let notice = availability?.notice {
            parts.append(notice)
        } else {
            parts.append(subtitle(session))
        }
        parts.append("스윙 \(session.swingCount)개")
        return parts.joined(separator: ", ")
    }

    static func subtitle(_ session: Session) -> String {
        [
            session.situation.label,
            session.observable.label,
            "클립 \(session.clips.count)개",
            "\(session.fps)fps",
        ].joined(separator: " · ")
    }
}
