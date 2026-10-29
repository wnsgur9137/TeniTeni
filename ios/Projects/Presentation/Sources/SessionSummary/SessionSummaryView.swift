import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

/// 세션 하나를 보여준다. 스윙이 없으면 **진단**으로 갈린다.
///
/// **탭바가 없다.** 흐름 중간이라 탭 이동이 세션을 끊는다
/// ([IA-FLOW](../../../../../docs/06-디자인/IA-FLOW.md) 10.2).
///
/// 목업: docs/06-디자인/_canvas/SessionSummary.dc.html · EmptySession.dc.html
public struct SessionSummaryView: View {
    @Bindable private var store: StoreOf<SessionSummaryFeature>

    public init(store: StoreOf<SessionSummaryFeature>) {
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

            case .loaded(let session):
                if session.swingCount == 0 {
                    EmptySessionView(
                        session: session,
                        onReframe: { store.send(.reframeTapped) },
                        onClose: { store.send(.closeTapped) }
                    )
                } else {
                    summary(session)
                }
            }
        }
        .task { store.send(.appeared) }
    }

    // MARK: 실패

    /// 조용히 빈 화면을 띄우지 않는다 — 사용자는 찍은 것이 사라졌다고 읽는다.
    private func failure(_ reason: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Token.State.warning)
            Text(reason)
                .font(.system(size: 17))
                .foregroundStyle(Token.Text.primary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("다시 시도") { store.send(.retryTapped) }
                    .buttonStyle(.borderedProminent)
                    .tint(Token.Accent.primary)
                Button("닫기") { store.send(.closeTapped) }
                    .tint(Token.Text.secondary)
            }
        }
        .padding(28)
    }

    // MARK: 요약

    private func summary(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(session)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    swingCountCard(session)
                    clipList(session)
                    // 점수·유형·문제 자리는 **만들지 않는다.** 그 데이터는
                    // 1-D 이후에 생긴다 — 빈 카드가 더 나쁘다(SPEC-0110).
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            footer
        }
    }

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("방금 연습")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Token.Text.primary)
            Text(subtitle(session))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func swingCountCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(session.swingCount)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Token.Text.primary)
            Text("스윙")
                .font(.system(size: 12))
                .foregroundStyle(Token.Text.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Token.Background.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("스윙 \(session.swingCount)개")
    }

    /// 클립을 머리로 두고 **스윙을 행으로** 펼친다.
    ///
    /// 전에는 클립만 보여줘서 누를 것이 없었다 — 목적지가 없었기 때문이다.
    /// 번호는 `ReplayItem.playlist(from:)`가 매긴 것을 그대로 쓴다. 두 화면이
    /// 다른 번호를 말하면 "12번째 스윙"이 어긋난다(SPEC-0123).
    @ViewBuilder
    private func clipList(_ session: Session) -> some View {
        let items = ReplayItem.playlist(from: session)
        VStack(alignment: .leading, spacing: 8) {
            Text("클립 \(session.clips.count)개")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Token.Text.tertiary)
            VStack(spacing: 1) {
                ForEach(session.clips) { clip in
                    clipHeader(clip)
                    ForEach(items.filter { $0.clipID == clip.id }) { item in
                        swingRow(item)
                    }
                }
            }
            .background(Token.Background.surface, in: .rect(cornerRadius: 13))
        }
    }

    private func clipHeader(_ clip: Clip) -> some View {
        HStack(spacing: 12) {
            // fps를 보여주는 이유: 발열로 강등되면 클립마다 다르다.
            // 그 사실이 드러나는 유일한 자리다(ADR-0005).
            Text("\(Self.time.string(from: clip.recordedAt)) · \(clip.fps)fps")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private func swingRow(_ item: ReplayItem) -> some View {
        Button { store.send(.swingTapped(item.swing.id)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("스윙 \(item.position)")
                        .font(.system(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(Token.Text.primary)
                    Text(Self.swingDetail(item.swing))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Token.Text.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Token.Text.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("스윙 \(item.position), \(Self.swingDetail(item.swing))")
        .accessibilityHint("리플레이를 엽니다")
    }

    /// 구간 길이와 **구간 안의** 임팩트 시각. 클립 기준 절대초를 보여주면
    /// 사용자가 어디를 말하는지 알 수 없다.
    static func swingDetail(_ swing: Swing) -> String {
        let impact = max(swing.impactSeconds - swing.startSeconds, 0)
        return String(format: "%.1f초 · 임팩트 %.2f초", max(swing.duration, 0), impact)
    }

    private var footer: some View {
        Button { store.send(.closeTapped) } label: {
            Text("완료")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Token.Text.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: 포매팅

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// 날짜 · 소요 · 상황. 소요를 모르면(종료 시각이 없으면) 생략한다 —
    /// "0초"로 적으면 거짓이다.
    private func subtitle(_ session: Session) -> String {
        var parts = [Self.date.string(from: session.startedAt)]
        if let duration = session.duration {
            parts.append(Self.duration(duration))
        }
        parts.append(session.situation.label)
        return parts.joined(separator: " · ")
    }

    /// 날짜 문구. 진단 화면도 같은 것을 쓴다.
    static func dateText(_ date: Date) -> String { Self.date.string(from: date) }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        return minutes > 0 ? "\(minutes)분 \(remainder)초" : "\(remainder)초"
    }
}
