import DesignSystem
import SwiftUI

/// 끝나지 않은 세션을 **복구하거나 폐기한다.**
///
/// ## 왜 복구가 위인가
///
/// 사용자가 잃은 것은 **영상**이다. 레퍼런스 조사에서 반복된 불만이 정확히
/// 그것이다 — TennisCut은 촬영 크래시로 녹화가 통째로 사라졌다
/// ([SwingVision](../../../../../docs/08-레퍼런스/SwingVision.md) 2026-10-27절).
/// 되돌릴 수 없는 폐기를 기본 동작 자리에 두지 않는다.
///
/// ## 왜 한 번 더 묻지 않는가
///
/// **이 시트가 확인이다.** "이 세션을 어떻게 할까"를 묻는 자리이고, 폐기
/// 버튼에 숫자와 "되돌릴 수 없습니다"가 붙어 있다. 여기서 또 물으면
/// 확인이 아니라 절차가 된다.
///
/// 목업: docs/06-디자인/_canvas/RecoverSheet.dc.html
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 5·6
struct RecoverSheet: View {

    let target: RecoverTarget
    let onRecover: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("지난 세션이\n끝나지 않았습니다")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Token.Text.primary)
                        .lineSpacing(2)
                    Text("앱이 예기치 않게 종료됐습니다. 찍힌 영상은 디스크에 남아 있습니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(Token.Text.secondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                meta

                // 영상이 하나도 없으면 복구 버튼을 두지 않는다 — 첫 프레임이
                // 오기 전에 죽은 세션이고, 눌러도 할 일이 없다.
                if target.canRecover {
                    recover
                } else if target.clipCount != nil {
                    Text("찍힌 영상이 없습니다. 복구할 것이 없습니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(Token.Text.secondary)
                }

                Divider().overlay(Token.Background.elevated)

                discard
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .background(Token.Background.surface)
        .presentationDragIndicator(.visible)
    }

    // MARK: 메타

    /// 촬영 시각 · 상황 · 정밀도 · 찾은 영상.
    ///
    /// 상황과 정밀도는 **레코드에서** 온다. 고아 `.mov`만으로는 복원되지
    /// 않는 값이고, 상황을 모르면 1-D 룰 판정이 무효가 된다
    /// (IA-FLOW 10.4). 그래서 촬영 시작 시 레코드를 연다.
    private var meta: some View {
        VStack(spacing: 10) {
            metaRow("촬영 시각", target.whenText)
            metaDivider
            metaRow("상황", target.situationText)
            metaDivider
            metaRow("정밀도", target.fpsText)
            metaDivider
            // 이 줄만 **스캔 결과**다. 레코드의 클립은 0개다.
            metaRow(
                "찾은 영상",
                target.clipCount.map { "클립 \($0)개" } ?? "확인 중…",
                accent: target.canRecover
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Token.Background.elevated, in: .rect(cornerRadius: 12))
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(Token.Background.base)
            .frame(height: 1)
    }

    private func metaRow(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Token.Text.tertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(accent ? Token.Accent.primary : Token.Text.primary)
        }
    }

    // MARK: 복구

    private var recover: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onRecover) {
                Text("복구한다")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Token.Text.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Token.Accent.primary, in: .rect(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            // ⚠️ 복구한 뒤 스윙 0개를 보고 "복구가 실패했나"로 읽으면
            //    안 된다. 미리 말한다.
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.State.warning)
                Text("스윙 구간은 없습니다. 분석 전에 종료됐습니다 — 영상은 재생할 수 있고, 스윙 단위 리플레이는 쓸 수 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Token.Text.secondary)
                    .lineSpacing(3)
            }
        }
    }

    // MARK: 폐기

    private var discard: some View {
        VStack(spacing: 7) {
            Button(action: onDiscard) {
                Text("폐기한다")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Token.State.error)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Token.State.error, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            // 무엇이 사라지는지 **숫자로** 적는다(#126과 같은 결정).
            // 스윙 수는 적지 않는다 — 모른다.
            Text(Self.discardNotice(target.clipCount))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Token.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// 확인 중에는 수를 적지 않는다 — **0개라고 쓰면 거짓이다**(아직 모른다).
    static func discardNotice(_ clipCount: Int?) -> String {
        guard let clipCount else { return "되돌릴 수 없습니다" }
        return "클립 \(clipCount)개를 지웁니다 · 되돌릴 수 없습니다"
    }
}
