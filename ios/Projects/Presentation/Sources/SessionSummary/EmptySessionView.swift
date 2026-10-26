import DesignSystem
import Domain
import SwiftUI

/// 스윙 0개 — **요약이 아니라 진단이다.**
///
/// 빈 요약을 보여주면 사용자는 **앱이 고장났다고 판단한다.** 원인을 짚어야
/// 한다([IA-FLOW](../../../../../docs/06-디자인/IA-FLOW.md)).
///
/// [#103](https://github.com/wnsgur9137/TeniTeni/issues/103) 때문에 실기기
/// 첫 시도에서 0개가 나올 개연성이 높다. 이 화면이 그때 사용자가 보는
/// 전부다.
///
/// 목업: docs/06-디자인/_canvas/EmptySession.dc.html
struct EmptySessionView: View {

    let session: Session
    let onReframe: () -> Void
    let onClose: () -> Void

    /// 확인 항목. 순서가 의미를 갖는다 — 가장 흔한 원인이 위다.
    private static let checks: [(title: String, detail: String)] = [
        ("선수가 프레임 안에 들어왔나요", "프레임 높이의 35~45%를 차지해야 합니다"),
        ("삼각대가 흔들리지 않았나요", "손에 들면 궤적을 잡지 못합니다"),
        ("거리가 5~8m 범위였나요", "기준은 6m, 허리 높이입니다"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text(subtitle)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Token.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 26)

            VStack(spacing: 18) {
                Image(systemName: "circle.slash")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Token.Text.tertiary)
                Text("스윙을 하나도\n찾지 못했습니다")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Token.Text.primary)
                    .multilineTextAlignment(.center)
                // 목업은 "영상은 저장하지 않았습니다"였는데 **사실이 아니다.**
                // 통영상은 남아 있고 지우는 코드가 없다 — SPEC-0110.
                Text("영상은 남아 있습니다.\n아래를 확인하고 다시 찍어보세요.")
                    .font(.system(size: 14))
                    .foregroundStyle(Token.Text.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 52)
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                ForEach(Array(Self.checks.enumerated()), id: \.offset) { index, check in
                    if index > 0 {
                        Divider().overlay(Token.Background.elevated).padding(.leading, 16)
                    }
                    checkRow(number: index + 1, title: check.title, detail: check.detail)
                }
            }
            .background(Token.Background.surface, in: .rect(cornerRadius: 13))
            .padding(.horizontal, 20)
            .padding(.top, 34)

            Spacer(minLength: 14)

            VStack(spacing: 10) {
                Button(action: onReframe) {
                    Text("배치 다시 보기")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Token.Text.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Token.Accent.primary, in: .rect(cornerRadius: 10))
                }
                Button(action: onClose) {
                    Text("닫기")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Token.Text.secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Token.Background.elevated, lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private func checkRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 15))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Token.Text.primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Text.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [SessionSummaryView.dateText(session.startedAt)]
        if let duration = session.duration {
            parts.append(SessionSummaryView.duration(duration))
        }
        parts.append(session.situation.label)
        return parts.joined(separator: " · ")
    }
}
