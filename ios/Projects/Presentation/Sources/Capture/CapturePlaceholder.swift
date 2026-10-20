import DesignSystem
import SwiftUI
import UIKit

/// 프리뷰가 없을 때 그 자리에 들어가는 화면. 가이드와 촬영이 같은 것을 쓴다 —
/// 두 벌로 두면 한쪽만 고치게 된다.
struct CapturePlaceholder: View {

    let status: CameraController.Status

    var body: some View {
        switch status {
        case .idle, .configuring:
            ProgressView("카메라 준비 중…")
                .tint(Token.Text.primary)
                .foregroundStyle(Token.Text.primary)

        case .permissionDenied:
            ContentUnavailableView {
                Label("카메라 권한이 필요합니다", systemImage: "camera.fill")
            } description: {
                Text("설정에서 카메라 접근을 허용해 주세요.")
            } actions: {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .tint(Token.Accent.primary)
            }

        case .failed(let reason):
            ContentUnavailableView {
                Label("카메라를 시작할 수 없습니다", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason)
            }

        case .ready, .recording:
            // 프리뷰가 있는 상태다. 호출하는 쪽이 이 분기로 오지 않는다.
            EmptyView()
        }
    }
}
