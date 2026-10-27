import ComposableArchitecture
import DesignSystem
import SwiftUI

/// 촬영 흐름의 바깥 껍데기. **카메라 세션과 프리뷰, 방향 잠금을 소유한다.**
///
/// 단계(가이드 → 촬영)가 바뀌어도 세션과 프리뷰 레이어는 그대로다. 프리뷰를
/// 분기 **안**에 두면 SwiftUI가 서브트리를 갈아끼우며 `AVCaptureVideoPreviewLayer`와
/// 커넥션을 다시 세운다 — 사용자가 맞춰 둔 구도 앞에서 화면이 한 번 꺼진다.
///
/// 근거: docs/07-기획/SPEC-0078-start-capture.md
public struct CaptureScreen: View {

    private let store: StoreOf<CaptureFeature>

    public init(store: StoreOf<CaptureFeature>, storage: SessionStorage) {
        self.store = store
        // 저장소는 진입점이 만들어 내려보낸다 — 프레임 경로는 TCA 바깥이다.
        _controller = State(initialValue: CameraController(storage: storage))
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: CameraController

    /// 프리뷰를 그릴 수 있는 상태인가. 아니면 그 자리에 사유가 들어간다.
    private var hasPreview: Bool {
        controller.status == .ready || controller.status == .recording
    }

    public var body: some View {
        ZStack {
            Token.Background.base.ignoresSafeArea()

            if hasPreview {
                CameraPreview(previewLayer: controller.previewLayer).ignoresSafeArea()
            } else {
                CapturePlaceholder(status: controller.status)
            }

            switch store.phase {
            case .framing:
                FramingGuideView(
                    guidance: store.state.guidance,
                    subject: store.state.subject,
                    canStart: hasPreview,
                    onStart: { store.send(.startTapped) },
                    onBack: { store.send(.closeTapped(savedSessionID: nil)) }
                )
            case .capturing:
                CaptureView(controller: controller) {
                    // 세션 저장은 비동기다. **기다린 뒤** 닫는다 — 정지
                    // 직후 닫으면 저장은 되는데 id가 없어 요약을 못 본다.
                    Task {
                        let id = await controller.finishPendingSession()
                        store.send(.closeTapped(savedSessionID: id))
                    }
                }
            }
        }
        .task {
            // 무엇을 찍는지 먼저 알려준다. 주 사용 손이 없으면 어느 손목을
            // 볼지 정할 수 없다.
            controller.configure(
                CameraController.CaptureContext(
                    handedness: store.state.handedness,
                    situation: store.state.situation,
                    observable: store.state.observable
                )
            )
            await controller.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // `Task { await controller.resume() }`를 여기서 만들지 않는다.
            // `scenePhase`는 `inactive → active → background`를 한 틱에
            // 몰아 주는데, 그러면 비동기 재개가 **동기 중단 뒤에** 깨어나
            // 백그라운드에서 카메라가 돈다 — #82.
            case .active: controller.enterForeground()
            case .inactive, .background: controller.suspend()
            @unknown default: break
            }
        }
        .onAppear { OrientationLock.shared.lock(to: CaptureScreen.supportedOrientations) }
        .onDisappear {
            // 세션을 먼저 내린다. 녹화 중에 닫히는 경로가 생기면 파일이
            // 마무리되지 않고 경과 시간 타이머가 런루프에 남는다.
            controller.suspend()
            // 풀지 않으면 세로 화면 12종이 가로로 남는다.
            OrientationLock.shared.release()
        }
    }
}

// MARK: - 방향

/// 앱 전체는 1-A에서 전 방향으로 풀렸으므로(세로 화면이 12종이다)
/// 이 화면이 스스로 잠근다. 시스템은 **창을 채우는 최상위 모달**에 방향을
/// 묻는데, SwiftUI에서는 그 호스팅 컨트롤러를 상속할 수 없어 마스크를
/// 홀더에 두고 진입점이 답한다.
/// 근거: docs/07-기획/SPEC-0061-module-shell.md 구현 선택지 3
extension CaptureScreen {
    public static var supportedOrientations: UIInterfaceOrientationMask { .landscape }
}
