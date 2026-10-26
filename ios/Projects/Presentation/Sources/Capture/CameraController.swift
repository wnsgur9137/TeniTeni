import DesignSystem
import AVFoundation
import ImageIO
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

    /// 포즈가 잡히는가. 6m 밖에서 "지금 내가 보이고 있는지"를 알려주는 유일한 수단이다.
    private(set) var poseStatus: PoseIndicator = .idle

    /// 마지막으로 포즈가 잡힌 **프레임 시각**. 깜빡임을 막는 기준이다 —
    /// 한 프레임 놓칠 때마다 표시가 바뀌면 6m 밖에서는 읽을 수 없다.
    ///
    /// 벽시계(`Date`)를 쓰지 않는다. 벽시계로 재면 "메인 액터에 결과가
    /// **배달된** 간격"을 재게 되는데, 녹화 시작처럼 메인이 수백 ms 막히는
    /// 순간에 쌓였던 결과가 한꺼번에 풀리면 프레임 간격이 8ms였는데도
    /// "끊겼다"고 판정한다.
    ///
    /// 표시가 아니라 판단용이므로 관측에서 뺀다 — 매 프레임 쓰기가 뷰
    /// 무효화를 일으키면 안 된다.
    @ObservationIgnored private var lastDetectedAt: TimeInterval?

    /// 마지막으로 적용한 결과의 프레임 시각. 비구조 `Task`는 생성 순서대로
    /// 실행되는 것이 보장되지 않으므로, 늦게 도착한 과거 결과를 버린다.
    @ObservationIgnored private var lastAppliedAt: TimeInterval?

    /// AVFoundation이 밀려서 버린 프레임 수. 포즈가 예산을 넘겼는지를
    /// 실기기에서 읽을 유일한 단서다.
    private(set) var droppedFrames: UInt64 = 0

    enum PoseIndicator: Equatable {
        /// 아직 프레임이 들어오지 않았다.
        case idle
        case detected
        case notFound
        /// 사람은 보이는데 어깨를 못 믿는다 — 측면으로 서면 이렇게 된다.
        case unusable
        case failed(String)
        /// 이 기기에서 분석 출력을 붙일 수 없다. 표시가 없는 것과
        /// 아직 프레임이 안 온 것을 구분한다.
        case unavailable(String)
    }

    /// 마이크 권한이 없으면 거짓. 무음으로 녹화하고 있다는 사실을 화면이 계속 보여줘야 한다 —
    /// 배너는 다른 메시지에 덮이고, 끝난 뒤에 알면 다시 찍을 수 없다.
    private(set) var recordsAudio: Bool = true
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

    // MARK: 분석 경로

    /// 프레임을 한 장씩 꺼내는 출력. 0-A의 통영상 녹화(`movieOutput`)와 **공존한다** —
    /// 녹화 경로를 건드리지 않으려고 출력을 더한다.
    private let videoOutput = AVCaptureVideoDataOutput()
    /// 콜백이 들어오는 전용 큐. 메인을 쓰면 UI가 프레임마다 막힌다.
    private let captureQueue = DispatchQueue(label: "com.wnsgur9137.TeniTeni.capture")
    private var intake: FrameIntake?
    private var analyzer: PoseAnalyzer?
    private var poseTask: Task<Void, Never>?

    // MARK: 구성

    func start() async {
        guard status == .idle || status == .permissionDenied else { return }
        status = .configuring

        let plan = await resolvePermissions()
        guard plan.allowsCapture else {
            status = .permissionDenied
            return
        }
        recordsAudio = plan.recordsAudio

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
            try configureSession(camera: camera, withAudio: plan.recordsAudio)
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        session.startRunning()
        applyFormat()
        startTrackingRotation(for: camera)
        startAnalysis()
        status = .ready
        // applyFormat이 이미 경고를 띄웠으면 덮지 않는다 — "120fps 포맷을 찾을 수 없습니다"가
        // 무음 안내보다 중하다. 무음은 표시줄에 계속 남으므로 배너를 양보해도 사라지지 않는다.
        if !recordsAudio, message == nil {
            message = "마이크 권한이 없어 무음으로 녹화합니다"
        }
    }

    /// 카메라를 먼저 해소한다. 카메라가 막히면 어차피 촬영이 없으므로 마이크는 묻지 않는다 —
    /// 쓰지도 못할 권한으로 다이얼로그를 한 번 더 띄우면 다음 요청의 거부율만 올린다.
    private func resolvePermissions() async -> CapturePermissionPlan {
        let camera = await resolve(.video)
        guard camera == .authorized else {
            return .make(camera: camera, microphone: .denied)
        }
        return .make(camera: camera, microphone: await resolve(.audio))
    }

    /// `.notDetermined`면 묻고 그 결과를 돌려준다. 나머지는 그대로 통과시킨다.
    private func resolve(_ media: AVMediaType) async -> AVAuthorizationStatus {
        let current = AVCaptureDevice.authorizationStatus(for: media)
        guard current == .notDetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: media) ? .authorized : .denied
    }

    private func configureSession(camera: AVCaptureDevice, withAudio: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 프리셋을 쓰지 않는다. activeFormat을 직접 고르기 위해 inputPriority로 둔다.
        session.sessionPreset = .inputPriority

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)

        if withAudio,
           let mic = AVCaptureDevice.default(for: .audio),
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

        configureAnalysisOutput()
    }

    /// 분석용 출력을 더한다. **실패해도 중단하지 않는다** — 녹화는 그대로
    /// 되고, 분석만 없는 상태가 된다. 기기에 따라 출력 조합이 거부될 수 있다.
    private func configureAnalysisOutput() {
        guard session.canAddOutput(videoOutput) else {
            // 배너는 다음 메시지에 덮인다. 지표 자리에도 사유를 남겨야
            // "표시가 없는 것"과 "아직 프레임이 안 온 것"이 구분된다.
            let reason = "이 기기에서는 녹화와 분석을 함께 할 수 없습니다"
            message = reason
            poseStatus = .unavailable(reason)
            return
        }
        // 밀리면 버린다. 붙들면 캡처 풀이 고갈된다 — 동시성 6.3.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        session.addOutput(videoOutput)
    }

    /// 분석을 시작한다. 포맷이 정해진 **뒤에** 불러야 한다 — 데시메이션 간격이
    /// 실제 fps에서 나온다.
    ///
    /// `AsyncStream`은 한 번 끝나면 다시 쓸 수 없으므로 분석기를 매번 새로
    /// 만든다. 세션이 멈췄다 다시 도는 경로(백그라운드 왕복)가 그래서 생긴다.
    private func startAnalysis() {
        guard session.outputs.contains(videoOutput), analyzer == nil else { return }

        let analyzer = PoseAnalyzer()
        let intake = FrameIntake(
            decimator: FrameDecimator(captureFPS: actualFPS),
            onAnalysisFrame: { [weak analyzer] frame in analyzer?.submit(frame) }
        )
        videoOutput.setSampleBufferDelegate(intake, queue: captureQueue)
        analyzer.update(orientation: visionOrientation)

        self.analyzer = analyzer
        self.intake = intake
        // 포획은 한 번만 한다. Task 안에서 다시 `[weak self]`를 쓰면 바깥의
        // 포획 변수를 동시 실행 코드에서 읽는 꼴이 된다.
        let sink: @Sendable (PoseOutcome) -> Void = { [weak self] outcome in
            Task { @MainActor in self?.apply(outcome) }
        }
        poseTask = Task { await analyzer.run(onOutcome: sink) }
    }

    private func stopAnalysis() {
        poseTask?.cancel()
        poseTask = nil
        analyzer?.finish()
        analyzer = nil
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        intake = nil
        // `.unavailable`은 기기의 성질이다. 멈췄다는 이유로 지우면
        // 사유가 사라지고 지표가 통째로 화면에서 없어진다.
        if case .unavailable = poseStatus {} else { poseStatus = .idle }
        lastDetectedAt = nil
        lastAppliedAt = nil
    }

    private func apply(_ outcome: PoseOutcome) {
        let seconds = outcome.seconds
        // 비구조 Task는 생성 순서대로 실행되지 않는다. 늦게 온 과거 결과가
        // 기준시를 과거로 되감으면 멀쩡한 상태에서 "끊겼다"가 뜬다.
        if let lastAppliedAt, seconds < lastAppliedAt { return }
        lastAppliedAt = seconds
        if case .detected = outcome { lastDetectedAt = seconds }

        guard let next = Self.indicator(
            for: outcome, lastDetectedAt: lastDetectedAt, grace: Self.poseGraceSeconds
        ) else { return }

        // `@Observable`의 setter는 값을 비교하지 않고 무조건 변경을 알린다.
        // 같은 값을 덮으면 **아무것도 바뀌지 않았는데** 초당 60회 뷰가
        // 무효화된다 — 메인이 가장 바쁜 녹화 중에.
        guard poseStatus != next else { return }
        poseStatus = next
    }

    /// 결과 하나를 표시로 바꾼다. `nil`이면 **바꾸지 않는다**(유예 중).
    ///
    /// 순수 함수로 빼 뒀다 — 카메라가 없으면 이 판단을 검증할 방법이 없고,
    /// 이것이 이 화면의 유일한 출력이다.
    static func indicator(
        for outcome: PoseOutcome,
        lastDetectedAt: TimeInterval?,
        grace: TimeInterval
    ) -> PoseIndicator? {
        switch outcome {
        case .detected:
            return .detected
        case .noPerson(let at):
            return settled(.notFound, at: at, lastDetectedAt: lastDetectedAt, grace: grace)
        case .unusable(let at):
            return settled(.unusable, at: at, lastDetectedAt: lastDetectedAt, grace: grace)
        case .failed(let reason, let at):
            // 한 프레임 오류로 "분석이 멈췄습니다"가 떴다 사라지면 읽을 수 없다.
            return settled(.failed(reason), at: at, lastDetectedAt: lastDetectedAt, grace: grace)
        }
    }

    /// 한 번도 잡힌 적 없으면 즉시 바꾼다. 잡힌 적이 있으면 유예를 기다린다.
    private static func settled(
        _ indicator: PoseIndicator,
        at seconds: TimeInterval,
        lastDetectedAt: TimeInterval?,
        grace: TimeInterval
    ) -> PoseIndicator? {
        guard let lastDetectedAt else { return indicator }
        return seconds - lastDetectedAt > grace ? indicator : nil
    }

    /// 포즈가 끊겼다고 표시할 때까지 기다리는 시간. 트리거의 `maximumGap`과 맞춘다 —
    /// 그보다 짧게 끊으면 트리거가 아직 이어가는 중에 화면만 끊겼다고 말한다.
    static let poseGraceSeconds: TimeInterval = SwingTriggerProfile.default.maximumGap

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

    /// 분석 버퍼가 세워진 방향. Vision에 넘기면 **좌표까지 맞춰** 돌려준다 —
    /// 버퍼를 돌리지 않아도 된다.
    private var visionOrientation: CGImagePropertyOrientation?

    /// 회전각 → 이미지 방향.
    ///
    /// **실기기에서 확인하지 못했다.** 다만 틀려도 기하는 무너지지 않는다 —
    /// 트리거가 쓰는 각속도 크기와 몸통선 교차 **부호 변화**는 화면 전체의
    /// 회전·거울에 불변이다. 영향은 "누워 있는 사람을 Vision이 못 찾는" 쪽이다.
    private static func orientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch Int(angle.rounded()) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }

    /// 녹화 중에는 방향을 바꾸지 않는다. 파일 중간에 회전이 바뀌면 안 된다.
    private func applyRotation(_ angle: CGFloat) {
        // 분석 방향은 녹화와 무관하다. 파일이 아니라 요청 인자이므로
        // 중간에 바뀌어도 이미 쓴 것이 망가지지 않는다.
        visionOrientation = Self.orientation(forRotationAngle: angle)
        analyzer?.update(orientation: visionOrientation)

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
        // 120fps면 포즈를 2프레임에 한 번만 돌린다. 포맷이 바뀌면 간격도 바뀐다.
        intake?.update(decimator: FrameDecimator(captureFPS: actualFPS))
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
        if let intake { droppedFrames = intake.droppedCount + intake.rejectedCount }
    }

    /// 실제 적용값을 다시 읽는다. 노출은 자동 모드에서 계속 변한다.
    func refreshActualValues() { readActualValues() }

    // MARK: 생명주기

    /// 백그라운드 진입. 녹화 중이면 먼저 정상 종료해 파일 손상을 막는다.
    func suspend() {
        stopAnalysis()
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
    ///
    /// 차단 화면에서 설정 앱으로 나갔다 돌아온 경우를 여기서 받는다. 다시 묻지 않으면
    /// 허용하고 돌아와도 차단 화면에 머문다 — 사용자는 앱이 고장났다고 판단한다.
    func resume() async {
        if status == .permissionDenied {
            await start()
            return
        }
        guard device != nil else { return }
        if case .failed = status { return }
        if !session.isRunning {
            session.startRunning()
            applyFormat()
            if let device { startTrackingRotation(for: device) }
            startAnalysis()
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

    /// `Task`는 그 자체가 보유 루트다. 취소하지 않으면 분석기 → 스트림 →
    /// 버퍼된 프레임 → 캡처 풀 IOSurface와 전송 세션·버퍼 풀이 `for await`에
    /// 정지한 채 남는다. 화면이 `suspend()`를 부르는 것이 정상 경로지만,
    /// 그것이 불리지 않는 경로에서도 새지 않게 한다.
    /// `isolated deinit`이라야 메인에 묶인 프로퍼티를 만질 수 있다.
    /// 평범한 `deinit`은 nonisolated여서 `poseTask`를 읽지 못한다.
    isolated deinit {
        poseTask?.cancel()
        elapsedTimer?.invalidate()
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
