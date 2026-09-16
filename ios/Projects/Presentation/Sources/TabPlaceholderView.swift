import DesignSystem
import SwiftUI

/// 아직 채워지지 않은 탭의 공통 표현.
///
/// "준비 중"이라고만 두지 않는다. **무엇이 올 자리인지**와 **왜 지금 비었는지**를
/// 함께 말해야 사용자가 고장으로 읽지 않는다.
public struct TabPlaceholderView: View {
    private let title: String
    private let message: String
    private let detail: String

    public init(title: String, message: String, detail: String) {
        self.title = title
        self.message = message
        self.detail = detail
    }

    public var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Token.Text.primary)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Token.Text.secondary)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Token.Text.tertiary)
            }
            .padding(.horizontal, 32)
        }
    }
}
