import DesignSystem
import SwiftUI

/// 보관함 탭의 자리.
///
/// 내용은 1-E가 채운다 (SwiftData 영속화 이후). 지금 비워두는 이유는
/// **탭이 눌리는데 아무것도 안 나오면 앱이 고장난 것처럼 보이기 때문**이다.
/// 근거: docs/06-디자인/IA-FLOW.md 10.4
public struct LibraryPlaceholderView: View {
    public init() {}

    public var body: some View {
        TabPlaceholderView(
            title: "보관함",
            message: "촬영한 세션이 여기 쌓입니다",
            detail: "아직 기록이 없습니다"
        )
    }
}
