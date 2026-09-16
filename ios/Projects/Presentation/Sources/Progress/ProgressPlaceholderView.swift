import DesignSystem
import SwiftUI

/// 진척도 탭의 자리.
///
/// 내용은 **2-E**가 채운다 (Swift Charts, 기간별 집계). 1-E가 아니다 —
/// docs/04-계획/WORK-PLAN.md 9.5.
public struct ProgressPlaceholderView: View {
    public init() {}

    public var body: some View {
        TabPlaceholderView(
            title: "진척도",
            message: "주 단위로 지표가 어떻게 변하는지 보여줍니다",
            detail: "세션이 쌓이면 나타납니다"
        )
    }
}
