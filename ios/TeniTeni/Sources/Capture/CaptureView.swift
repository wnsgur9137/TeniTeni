import SwiftUI
import TeniVision

struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = CameraController()
    @State private var showInspector = false
    @State private var customDistance = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.status {
            case .idle, .configuring:
                ProgressView("카메라 준비 중…").tint(.white).foregroundStyle(.white)
            case .permissionDenied:
                permissionDenied
            case .failed(let reason):
                failure(reason)
            case .ready, .recording:
                CameraPreview(session: controller.session).ignoresSafeArea()
                overlay
            }
        }
        .task { await controller.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: controller.resume()
            case .inactive, .background: controller.suspend()
            @unknown default: break
            }
        }
        .sheet(isPresented: $showInspector) { FormatInspectorView() }
    }

    // MARK: 오버레이

    private var overlay: some View {
        VStack {
            actualValuesBar
            Spacer()
            if let message = controller.message {
                Text(message)
                    .font(.caption)
                    .padding(8)
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            controls
        }
        .padding()
    }

    /// 요청값이 아니라 device에서 읽은 실제 적용값을 보여준다.
    /// 시스템이 요청을 거부하거나 조정할 수 있고, 그걸 알아야 한다.
    private var actualValuesBar: some View {
        HStack(spacing: 14) {
            label("실제 fps", String(format: "%.0f", controller.actualFPS))
            label("노출", exposureText)
            label("ISO", String(format: "%.0f", controller.actualISO))
            label("해상도", controller.actualResolution)
            label("화각", String(format: "%.1f°", controller.actualFieldOfView))
            if controller.isBinned {
                Text("binned").font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            Button { showInspector = true } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .tint(.white)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 10))
        .onTapGesture { controller.refreshActualValues() }
    }

    private var exposureText: String {
        let seconds = controller.actualExposureSeconds
        guard seconds > 0 else { return "-" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.white.opacity(0.6))
            Text(value).bold()
        }
    }

    // MARK: 컨트롤

    private var controls: some View {
        VStack(spacing: 12) {
            qualityPicker
            HStack(spacing: 12) {
                exposurePicker
                distanceField
            }
            recordButton
        }
        .padding(14)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 14))
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("촬영 품질").font(.caption).foregroundStyle(.white.opacity(0.7))
            Picker("촬영 품질", selection: Binding(
                get: { controller.quality },
                set: { controller.quality = $0; controller.applyFormat() }
            )) {
                ForEach(CaptureQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!controller.supports120 || controller.status == .recording)

            Text(controller.supports120
                 ? controller.quality.detail
                 : "이 기기는 120fps를 지원하지 않아 60fps로 고정됩니다")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var exposurePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("노출").font(.caption).foregroundStyle(.white.opacity(0.7))
            Picker("노출", selection: Binding(
                get: { controller.exposure },
                set: { controller.exposure = $0; controller.applyFormat() }
            )) {
                ForEach(ExposureSetting.allCases) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controller.status == .recording)
            Text(controller.exposure.detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var distanceField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("거리").font(.caption).foregroundStyle(.white.opacity(0.7))
            Picker("거리", selection: Binding(
                get: { controller.distanceMeters },
                set: { controller.distanceMeters = $0 }
            )) {
                ForEach(DistancePreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: 180)
    }

    private var recordButton: some View {
        Button {
            controller.toggleRecording()
        } label: {
            Circle()
                .fill(controller.status == .recording ? .white : .red)
                .frame(width: 64, height: 64)
                .overlay {
                    if controller.status == .recording {
                        RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 24, height: 24)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 실패 상태

    private var permissionDenied: some View {
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
        }
    }

    private func failure(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("카메라를 시작할 수 없습니다", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        }
    }
}
