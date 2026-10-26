import DesignSystem
import SwiftUI
import TeniVision

/// 0-A 촬영 화면.
///
/// **사용자는 코트에 있고 폰은 6m 떨어진 삼각대에 있다.**
/// docs/06-디자인/IA-FLOW.md 10.5절이 이 화면의 규칙을 정한다 —
/// 촬영 중에는 수치·설정을 표시하지 않는다. 읽을 수 없고, 읽으려
/// 다가오면 촬영이 끊긴다.
///
/// 목업: docs/06-디자인/_canvas/CaptureContinuous.dc.html · CaptureWarning.dc.html
struct CaptureView: View {

    /// 세션과 생명주기는 `CaptureScreen`이 소유한다. 이 화면은 그리고 보낼 뿐이다 —
    /// 가이드와 촬영이 세션을 공유해야 구도를 맞춘 화면이 꺼지지 않는다.
    private let controller: CameraController
    private let onClose: () -> Void

    init(controller: CameraController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
    }

    @State private var showInspector = false

    private var isRecording: Bool { controller.status == .recording }

    /// 배경·프리뷰·실패 화면은 `CaptureScreen`이 깐다. 이 뷰는 그 위에
    /// 얹는 것만 그린다 — 단계가 바뀌어도 프리뷰 레이어가 다시 세워지지 않는다.
    var body: some View {
        ZStack {
            if controller.status == .ready || controller.status == .recording {
                bottomScrim
                overlay
            }
        }
        // 상태를 화면 테두리 색으로 — 6m에서 읽히는 유일한 상태 표현이다
        .overlay(alignment: .center) { statusBorder }
        // 어떤 상태에서도 나갈 수 있어야 한다. 카메라가 실패하면 아래 컨트롤이
        // 통째로 안 그려지므로, 닫기를 상태 분기 밖에 둔다.
        .overlay(alignment: .topLeading) { closeButton }
        .sheet(isPresented: $showInspector) { FormatInspectorView() }
    }

    /// 녹화 중에는 그리지 않는다 — 6m 밖에서 잘못 눌러도 알아채지 못한다.
    /// 정지한 뒤에 닫는다.
    @ViewBuilder
    private var closeButton: some View {
        if !isRecording {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Token.Text.primary)
                    .frame(width: 44, height: 44)
                    .background(Token.Background.scrim, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("촬영 닫기")
            .padding(.leading, 16)
            .padding(.top, 10)
        }
    }

    // MARK: 상태 테두리

    /// 정상이면 없음, 경고가 있으면 오렌지. IA-FLOW 10.5의 "이상 상태" 표현이다.
    @ViewBuilder
    private var statusBorder: some View {
        if controller.message != nil {
            Rectangle()
                .strokeBorder(Token.State.warning, lineWidth: 3)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// 하단 컨트롤이 영상 위에서 읽히도록 어둡게 깐다.
    private var bottomScrim: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [Token.Background.base.opacity(0), Token.Background.base.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 오버레이

    private var overlay: some View {
        ZStack {
            // 녹화 중에는 설정을 아예 렌더하지 않는다. 흐리게 두면 6m에서
            // "뭔가 있는데 안 읽히는 것"이 되어 오히려 다가오게 만든다.
            if !isRecording {
                VStack {
                    actualValuesBar
                        .padding(.leading, 56)   // 닫기 버튼 자리를 비운다
                    Spacer()
                    controls
                }
                .padding()
            }

            elapsedTime
            swingCount
            storageWarning
            poseIndicator
            warningBanner
            recordButton
        }
    }

    // MARK: 포즈 — "지금 내가 보이고 있는가"

    /// 6m 밖에서 읽혀야 하는 상태다. 사람이 프레임에서 벗어나면 스윙이 하나도
    /// 잡히지 않는데, 그 사실을 끝나고 알면 다시 찍을 수밖에 없다.
    ///
    /// 수치가 아니라 **상태**이므로 녹화 중에도 남는다(IA-FLOW 10.5).
    @ViewBuilder
    private var poseIndicator: some View {
        if let label = poseLabel {
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Circle()
                            .fill(poseTint)
                            .frame(width: 14, height: 14)
                        Text(label)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Token.Text.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Token.Background.scrim, in: .capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label)
                }
                Spacer()
            }
            .padding(.trailing, 16)
            .padding(.top, 14)
            .allowsHitTesting(false)
        }
    }

    private var poseLabel: String? {
        switch controller.poseStatus {
        case .idle: nil
        case .detected: "사람이 보입니다"
        case .notFound: "사람이 안 보입니다"
        // "안 보인다"와 합치면 프레임 안에 멀쩡히 있는 사람이 자리를 옮긴다.
        case .unusable: "자세가 잘 안 보입니다"
        case .failed: "포즈 분석이 멈췄습니다"
        case .unavailable: "이 기기에서는 분석을 할 수 없습니다"
        }
    }

    private var poseTint: Color {
        switch controller.poseStatus {
        case .detected: Token.State.success
        case .notFound, .unusable, .failed, .unavailable: Token.State.warning
        case .idle: Token.Text.tertiary
        }
    }

    // MARK: 경과 시간 — 6m에서 읽혀야 하는 첫 번째 정보

    /// 목업의 스윙 카운트 자리다. 0-A에는 셀 스윙이 없으므로 경과 시간을 둔다.
    /// 스윙 검출은 1-B다.
    @ViewBuilder
    private var elapsedTime: some View {
        if isRecording {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedElapsed)
                            .font(.system(size: 72, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Token.Text.primary)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Token.State.error)
                                .frame(width: 10, height: 10)
                            Text(recordingSummary)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Token.Text.secondary)
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(32)
            .allowsHitTesting(false)
        }
    }

    /// 무음이면 그 사실을 녹화 중에도 계속 보여준다. 배너는 다른 메시지에 덮인다.
    private var recordingSummary: String {
        let base = "녹화 중 · \(Int(controller.actualFPS))fps · \(controller.exposure.title)"
        return controller.recordsAudio ? base : base + " · 무음"
    }

    // MARK: 스윙 카운트 — 6m에서 읽혀야 하는 결과

    /// 경과 시간 아래에 둔다. 사용자가 알고 싶은 것은 "몇 분 찍었나"가
    /// 아니라 **"몇 개 잡혔나"**다 — 하나도 안 잡히면 자리가 틀렸다는
    /// 뜻이고, 그걸 끝난 뒤에 알면 다시 찍어야 한다.
    @ViewBuilder
    private var swingCount: some View {
        if isRecording {
            VStack {
                Spacer()
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(controller.swingClipCount)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Token.Text.primary)
                        Text("스윙")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Token.Text.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("스윙 \(controller.swingClipCount)개")
                    Spacer()
                }
                .padding(.leading, 24)
                .padding(.bottom, 20)
            }
            .allowsHitTesting(false)
        }
    }

    /// 저장이 막혔으면 녹화 중에도 계속 보여준다. 배너는 덮이고,
    /// 끝난 뒤에 알면 다시 찍을 수 없다.
    @ViewBuilder
    private var storageWarning: some View {
        if let failure = controller.storageFailure {
            VStack {
                Spacer()
                Text(failure)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Token.Text.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Token.State.warning.opacity(0.9), in: .capsule)
                    .padding(.bottom, 92)
            }
            .allowsHitTesting(false)
        }
    }

    private var formattedElapsed: String {
        let total = Int(controller.recordedDuration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 경고는 상단 중앙. 테두리 색과 함께 쓴다 — 색만으로 정보를 전달하지 않는다.
    @ViewBuilder
    private var warningBanner: some View {
        if let message = controller.message {
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Token.State.warning)
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Token.Text.primary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Token.Background.scrim, in: .rect(cornerRadius: 10))
                Spacer()
            }
            .padding(.top, 24)
            .allowsHitTesting(false)
        }
    }

    // MARK: 실제 적용값

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
                Text("binned")
                    .font(.caption2)
                    .foregroundStyle(Token.State.warning)
            }
            if !controller.recordsAudio {
                Label("무음", systemImage: "mic.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(Token.State.warning)
            }
            // 포즈가 예산을 넘겼는지를 실기기에서 읽을 유일한 단서다.
            // 0이면 띄우지 않는다 — 표시줄은 이미 빽빽하다.
            if controller.droppedFrames > 0 {
                Label("드롭 \(controller.droppedFrames)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Token.State.warning)
            }
            Spacer()
            Button { showInspector = true } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .tint(Token.Accent.primary)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Token.Text.primary)
        .padding(10)
        .background(Token.Background.scrim, in: .rect(cornerRadius: 10))
        .onTapGesture { controller.refreshActualValues() }
    }

    private var exposureText: String {
        let seconds = controller.actualExposureSeconds
        guard seconds > 0 else { return "-" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(Token.Text.tertiary)
            Text(value).bold()
        }
    }

    // MARK: 컨트롤 — 녹화 중에는 렌더되지 않는다

    private var controls: some View {
        VStack(spacing: 12) {
            qualityPicker
            HStack(spacing: 12) {
                exposurePicker
                distanceField
            }
        }
        .padding(14)
        .background(Token.Background.scrim, in: .rect(cornerRadius: 14))
        .padding(.trailing, 96)   // 녹화 버튼 자리를 비운다
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("촬영 품질").font(.caption).foregroundStyle(Token.Text.secondary)
            Picker("촬영 품질", selection: Binding(
                get: { controller.quality },
                set: { controller.quality = $0; controller.applyFormat() }
            )) {
                ForEach(CaptureQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!controller.supports120)

            Text(controller.supports120
                 ? controller.quality.detail
                 : "이 기기는 120fps를 지원하지 않아 60fps로 고정됩니다")
                .font(.caption2)
                .foregroundStyle(Token.Text.tertiary)
        }
    }

    private var exposurePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("노출").font(.caption).foregroundStyle(Token.Text.secondary)
            Picker("노출", selection: Binding(
                get: { controller.exposure },
                set: { controller.exposure = $0; controller.applyFormat() }
            )) {
                ForEach(ExposureSetting.allCases) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            .pickerStyle(.segmented)
            Text(controller.exposure.detail)
                .font(.caption2)
                .foregroundStyle(Token.Text.tertiary)
        }
    }

    private var distanceField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("거리").font(.caption).foregroundStyle(Token.Text.secondary)
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

    // MARK: 녹화 버튼 — 우측 중앙 고정

    /// 목업과 같은 72pt. 화면 어디에 있든 손이 닿는 자리가 아니라
    /// **6m 밖에서 어디를 눌러야 하는지 아는 자리**에 둔다.
    private var recordButton: some View {
        HStack {
            Spacer()
            Button {
                controller.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(Token.Background.scrim)
                        .overlay(Circle().strokeBorder(Token.Text.primary, lineWidth: 3))
                    if isRecording {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Token.State.error)
                            .frame(width: 26, height: 26)
                    } else {
                        Circle()
                            .fill(Token.State.error)
                            .frame(width: 52, height: 52)
                    }
                }
                .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "녹화 정지" : "녹화 시작")
        }
        .padding(.trailing, 32)
    }

}
