import ComposableArchitecture
import SwiftUI

/// 촬영 흐름의 바깥 껍데기. **카메라 세션과 방향 잠금을 소유한다.**
///
/// 단계(가이드 → 촬영)가 바뀌어도 세션은 그대로다. 세션을 다시 세우면
/// 사용자가 맞춰 둔 구도 앞에서 화면이 한 번 꺼진다.
///
/// 근거: docs/07-기획/SPEC-0078-start-capture.md
public struct CaptureScreen: View {

    @Bindable private var store: StoreOf<CaptureFeature>

    public init(store: StoreOf<CaptureFeature>) {
        self.store = store
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = CameraController()

    public var body: some View {
        ZStack {
            switch store.phase {
            case .framing:
                FramingGuideView(
                    guidance: store.state.guidance,
                    subject: store.state.subject,
                    controller: controller,
                    onStart: { store.send(.startTapped) },
                    onBack: { store.send(.closeTapped) }
                )
            case .capturing:
                CaptureView(controller: controller) { store.send(.closeTapped) }
            }
        }
        .task { await controller.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await controller.resume() }
            case .inactive, .background: controller.suspend()
            @unknown default: break
            }
        }
        // 촬영은 가로 고정이다. 나갈 때 반드시 풀어야 세로 화면이 돌아온다.
        .onAppear { OrientationLock.shared.lock(to: CaptureScreen.supportedOrientations) }
        .onDisappear { OrientationLock.shared.release() }
    }
}

// MARK: - 방향

/// 앱 전체는 1-A에서 전 방향으로 풀렸으므로(세로 화면이 12종이다)
/// 이 화면이 스스로 잠근다.
/// 근거: docs/07-기획/SPEC-0061-module-shell.md 구현 선택지 3
extension CaptureScreen {
    public static var supportedOrientations: UIInterfaceOrientationMask { .landscape }
}
