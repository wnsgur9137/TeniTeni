import AVFoundation
import SwiftUI
import UIKit

/// `AVPlayerLayer`를 SwiftUI에 꽂는다. `CameraPreview`와 같은 구조다 —
/// 레이어를 뷰가 만들지 않고 **받는다.** 그래야 화면이 다시 그려져도
/// 플레이어가 새로 서지 않는다.
struct PlayerLayerView: UIViewRepresentable {
    let layer: AVPlayerLayer

    func makeUIView(context: Context) -> LayerHostView {
        LayerHostView(playerLayer: layer)
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        private let playerLayer: AVPlayerLayer

        init(playerLayer: AVPlayerLayer) {
            self.playerLayer = playerLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("코드로만 만든다") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
