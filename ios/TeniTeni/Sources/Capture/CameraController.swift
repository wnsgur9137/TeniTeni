import AVFoundation
import Observation
import TeniVision
import UIKit

/// Phase 0-A 최소 촬영 컨트롤러.
///
/// 이 클래스는 의도적으로 @MainActor에 묶여 있다. 0-A의 목적은 실기기에서
/// 포맷·노출을 확인하고 영상을 얻는 것이지 실시간 파이프라인이 아니다.
/// 0-D에서 docs/02-설계/CONCURRENCY.md 6.2절의 actor 배치로 재작성한다.
@MainActor
@Observable
final class CameraController: NSObject {

    // MARK: 상태

    enum Status: Equatable {
        case idle
        case permissionDenied
        case configuring
        case ready
        case recording
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// 요청값 — 사용자가 고른 것
    var quality: CaptureQuality = .precise
    var exposure: ExposureSetting = .fast1000
    var distanceMeters: Double = DistancePreset.recommended.rawValue

    /// 실제 적용값 — 시스템이 조정할 수 있으므로 별도로 읽어 표시한다
    private(set) var actualFPS: Double = 0
    private(set) var actualExposureSeconds: Double = 0
    private(set) var actualISO: Float = 0
    private(set) var actualResolution: String = "-"
    private(set) var actualFieldOfView: Float = 0
    private(set) var isBinned: Bool = false

    private(set) var supports120: Bool = false
    private(set) var lastSavedURL: URL?
    private(set) var message: String?

    /// 녹화 경과 시간 (초). 6m 밖에서 읽히는 유일한 수치이므로
    /// 화면이 이 값을 초 단위로 갱신한다 (docs/06-디자인/IA-FLOW.md 10.5).
    private(set) var recordedDuration: TimeInterval = 0

    // MARK: 세션

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var elapsedTimer: Timer?
    private var pendingMetadata: ClipMetadata?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    // MARK: 구성

    func start() async {
        guard status == .idle || status == .permissionDenied else { return }
        status = .configuring

        guard await requestAccess() else {
            status = .permissionDenied
            return
        }

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            status = .failed("후면 광각 카메라를 찾을 수 없습니다")
            return
        }
        device = camera
        supports120 = FormatSelector.supports(camera, fps: 120)
        if !supports120 { quality = .standard }

        do {
            try configureSession(camera: camera)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        session.startRunning()
        applyFormat()
        startTrackingRotation(for: camera)
        status = .ready
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureSession(camera: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 프리셋을 쓰지 않는다. activeFormat을 직접 고르기 위해 inputPriority로 둔다.
        session.sessionPreset = .inputPriority

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(movieOutput)

        // 120fps는 분당 용량이 크다. 방치되면 저장공간이 고갈되므로 상한을 둔다.
        movieOutput.maxRecordedDuration = CMTime(seconds: 600, preferredTimescale: 600)

        // 고정 카메라 전제이므로 안정화를 끈다.
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
    }

    // MARK: 회전

    /// 녹화 영상의 방향 메타데이터를 기기 방향에 맞춘다.
    /// 이게 없으면 0-C 오프라인 분석에서 좌표계가 틀어진다.
    private func startTrackingRotation(for device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)

        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: [.new]
        ) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.applyRotation(angle)
            }
        }
    }

    /// 녹화 중에는 방향을 바꾸지 않는다. 파일 중간에 회전이 바뀌면 안 된다.
    private func applyRotation(_ angle: CGFloat) {
        guard !movieOutput.isRecording,
              let connection = movieOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: 포맷 · 노출 적용

    /// activeFormat → activeVideoMinFrameDuration 순서가 중요하다.
    /// 포맷을 바꾸면 프레임 듀레이션이 리셋된다.
    /// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.2절
    func applyFormat() {
        guard let device else { return }
        // 녹화 중 세션 구성을 바꾸면 파일이 손상된다.
        guard !movieOutput.isRecording else {
            message = "녹화 중에는 설정을 바꿀 수 없습니다"
            return
        }
        let targetFPS = quality.fps

        guard let format = FormatSelector.format(in: device, targetFPS: targetFPS) else {
            message = "\(Int(targetFPS))fps 포맷을 찾을 수 없습니다"
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration

            applyExposure(to: device, format: format)
        } catch {
            message = "포맷 설정 실패: \(error.localizedDescription)"
            return
        }

        readActualValues()
    }

    private func applyExposure(to device: AVCaptureDevice, format: AVCaptureDevice.Format) {
        guard let spec = exposure.duration else {
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            return
        }
        guard device.isExposureModeSupported(.custom) else {
            message = "이 기기는 수동 노출을 지원하지 않습니다"
            return
        }
        var target = CMTime(value: CMTimeValue(spec.numerator), timescale: spec.denominator)
        // 포맷이 허용하는 범위로 클램프
        if CMTimeCompare(target, format.minExposureDuration) < 0 {
            target = format.minExposureDuration
            message = "요청 노출이 너무 짧아 \(fraction(target))로 조정됨"
        } else if CMTimeCompare(target, format.maxExposureDuration) > 0 {
            target = format.maxExposureDuration
            message = "요청 노출이 너무 길어 \(fraction(target))로 조정됨"
        }
        device.setExposureModeCustom(duration: target, iso: AVCaptureDevice.currentISO)
    }

    private func readActualValues() {
        guard let device else { return }
        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        actualResolution = "\(dims.width)×\(dims.height)"
        actualFieldOfView = format.videoFieldOfView
        isBinned = format.isVideoBinned
        let minDuration = device.activeVideoMinFrameDuration
        actualFPS = minDuration.seconds > 0 ? 1.0 / minDuration.seconds : 0
        actualExposureSeconds = device.exposureDuration.seconds
        actualISO = device.iso
    }

    /// 실제 적용값을 다시 읽는다. 노출은 자동 모드에서 계속 변한다.
    func refreshActualValues() { readActualValues() }

    // MARK: 생명주기

    /// 백그라운드 진입. 녹화 중이면 먼저 정상 종료해 파일 손상을 막는다.
    func suspend() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            message = "백그라운드 진입으로 녹화를 종료했습니다"
        }
        if session.isRunning { session.stopRunning() }
    }

    /// 포그라운드 복귀. 세션을 재시작하고 포맷·노출을 다시 적용한다.
    /// 세션이 멈추면 커스텀 노출이 리셋되므로 applyFormat 재호출이 필수다.
    func resume() {
        guard device != nil, status != .permissionDenied else { return }
        if case .failed = status { return }
        if !session.isRunning {
            session.startRunning()
            applyFormat()
            if let device { startTrackingRotation(for: device) }
        }
    }

    // MARK: 녹화

    func toggleRecording() {
        movieOutput.isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard let device, status == .ready else { return }
        readActualValues()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let name = "\(stamp)_\(Int(actualFPS))fps_\(exposure.rawValue)_\(Int(distanceMeters))m.mov"
        let url = URL.documentsDirectory.appending(path: name)

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let model = DeviceIdentifier.current

        pendingMetadata = ClipMetadata(
            recordedAt: Date(),
            fileName: name,
            requestedFPS: quality.fps,
            requestedExposure: exposure.rawValue,
            actualFPS: actualFPS,
            actualExposureSeconds: actualExposureSeconds,
            actualISO: actualISO,
            distanceMeters: distanceMeters,
            width: dims.width,
            height: dims.height,
            videoFieldOfView: actualFieldOfView,
            isVideoBinned: isBinned,
            deviceModel: model,
            systemVersion: UIDevice.current.systemVersion,
            cameraType: device.deviceType.rawValue
        )

        movieOutput.startRecording(to: url, recordingDelegate: self)
        status = .recording
        startElapsedTimer()
    }

    // MARK: 경과 시간

    /// `movieOutput.recordedDuration`을 직접 읽는다. 자체 카운터를 두면
    /// 실제 기록 길이와 어긋난다 — 세션이 잠시 멈춰도 시계는 흐른다.
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        recordedDuration = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = CMTimeGetSeconds(self.movieOutput.recordedDuration)
                self.recordedDuration = seconds.isFinite && seconds > 0 ? seconds : 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordedDuration = 0
    }

    private func stopRecording() {
        movieOutput.stopRecording()
    }

    private func fraction(_ time: CMTime) -> String {
        let seconds = time.seconds
        guard seconds > 0 else { return "-" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    enum CaptureError: LocalizedError {
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .cannotAddInput: "카메라 입력을 추가할 수 없습니다"
            case .cannotAddOutput: "녹화 출력을 추가할 수 없습니다"
            }
        }
    }
}

// MARK: - 녹화 델리게이트

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let failure = error?.localizedDescription
        Task { @MainActor in
            // 녹화가 끝나는 모든 경로(정지·실패·suspend)가 이 델리게이트를
            // 거치므로 타이머 정리를 여기 한 곳에 둔다.
            self.stopElapsedTimer()
            self.status = .ready
            if let failure {
                self.message = "녹화 실패: \(failure)"
                return
            }
            if let metadata = self.pendingMetadata {
                do {
                    try metadata.write(besides: outputFileURL)
                } catch {
                    self.message = "메타데이터 저장 실패: \(error.localizedDescription)"
                }
                self.pendingMetadata = nil
            }
            self.lastSavedURL = outputFileURL
            self.message = "저장됨: \(outputFileURL.lastPathComponent)"
        }
    }
}
