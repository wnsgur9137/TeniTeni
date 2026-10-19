import AVFoundation

/// 권한 상태가 촬영을 어떻게 바꾸는지 한곳에 모은다.
///
/// 카메라가 없으면 찍을 것이 없으므로 막는다. 마이크는 없어도 **무음으로 계속**한다 —
/// 소리는 이 앱의 핵심이 아니고, 여기서 막으면 스윙 기록 전체를 잃는다.
/// 근거: docs/06-디자인/IA-FLOW.md 10.6 예외 경로.
public enum CapturePermissionPlan: Equatable, Sendable {
    /// 촬영할 수 없다. 차단 화면을 띄우고 설정 앱으로 보낸다.
    case blocked
    /// 촬영한다. `audio`가 거짓이면 마이크 입력 없이 구성한다.
    case proceed(audio: Bool)

    /// `.notDetermined`는 호출 전에 요청해 해소한다. 해소하지 않고 넘기면
    /// "아직 묻지 않았다"를 "거부했다"로 취급하므로 여기서도 막고 끈다.
    public static func make(
        camera: AVAuthorizationStatus,
        microphone: AVAuthorizationStatus
    ) -> Self {
        guard camera == .authorized else { return .blocked }
        return .proceed(audio: microphone == .authorized)
    }

    public var allowsCapture: Bool {
        if case .proceed = self { return true }
        return false
    }

    public var recordsAudio: Bool {
        if case .proceed(let audio) = self { return audio }
        return false
    }
}
