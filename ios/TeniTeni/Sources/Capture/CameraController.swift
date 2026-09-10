import AVFoundation
import Observation
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

    // MARK: 세션

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var pendingMetadata: ClipMetadata?

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

        // 고정 카메라 전제이므로 안정화를 끈다.
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
    }

    // MARK: 포맷 · 노출 적용

    /// activeFormat → activeVideoMinFrameDuration 순서가 중요하다.
    /// 포맷을 바꾸면 프레임 듀레이션이 리셋된다.
    /// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.2절
    func applyFormat() {
        guard let device else { return }
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
