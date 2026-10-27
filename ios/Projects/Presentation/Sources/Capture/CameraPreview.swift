import AVFoundation
import SwiftUI

/// 0-A는 기본 프리뷰 레이어를 쓴다.
/// Metal 직접 렌더는 0-D 작업이다 (docs/05-결정/stack/D-07-overlay-rendering.md).
///
/// **레이어를 만들지 않는다.** `CameraController`가 소유한 것을 받아서 꽂는다 —
/// 회전 좌표기(`RotationCoordinator`)는 **생성 시점에** 프리뷰 레이어를 받아야
/// `videoRotationAngleForHorizonLevelPreview`를 내는데, 뷰가 레이어를 만들면
/// 좌표기가 세워지는 `start()` 시점에 아직 레이어가 없다
/// ([#82](https://github.com/wnsgur9137/TeniTeni/issues/82)).
struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        PreviewView(previewLayer: previewLayer)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 암묵적 애니메이션을 끈다. 켜 두면 방향 전환마다 프리뷰가
            // 한 번 밀려 들어오고, 6m 밖에서는 그게 흔들림으로 보인다.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
