import AVFoundation
import Foundation

/// 세션이 스스로 멈췄을 때 무엇을 하고 무엇을 말할지.
///
/// ## 왜 값으로 빼는가
///
/// 전화를 받거나 다른 앱이 카메라를 가져가는 경로는 **실기기에서만 벌어진다.**
/// 알림 처리를 `CameraController` 안에 두면 그 판단이 영원히 검증되지 않는다.
/// 사유 → 조치의 대응만 떼어 놓으면 전수로 확인할 수 있다.
///
/// ## 사유마다 조치가 다르다
///
/// 카메라를 잃은 중단은 **녹화를 끝내야 한다** — 파일을 마무리하지 않으면
/// 재생할 수 없는 조각이 남고, 세션도 닫히지 않아 그동안의 클립이 통째로
/// 사라진다. 반면 마이크만 빼앗긴 중단은 영상이 계속 들어오므로 끊을 이유가
/// 없다.
///
/// 근거: [#100](https://github.com/wnsgur9137/TeniTeni/issues/100)
struct CaptureInterruption: Equatable, Sendable {

    /// 6m 밖에서 읽힐 한 줄. 왜 멈췄는지 모르면 사용자는 앱이 고장났다고 읽는다.
    let message: String

    /// 녹화를 정상 종료해야 하는가.
    let endsRecording: Bool

    /// 중단이 끝났을 때 분석을 다시 세워야 하는가.
    ///
    /// `AVCaptureSession`은 중단이 끝나면 **스스로 다시 돈다.** 그래서
    /// "세션이 멈춰 있으면 세운다"는 조건으로는 분석이 되살아나지 않는다 —
    /// 세션은 이미 돌고 있고 분석만 죽어 있다.
    let needsRestart: Bool

    static func make(reason: AVCaptureSession.InterruptionReason?) -> CaptureInterruption {
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            // 백그라운드 진입은 `scenePhase`가 먼저 받는다. 여기 오는 것은
            // 그 경로를 타지 않은 경우이므로 같은 조치를 한다.
            return CaptureInterruption(
                message: "앱이 내려가 촬영을 멈췄습니다",
                endsRecording: true,
                needsRestart: true
            )

        case .videoDeviceInUseByAnotherClient:
            return CaptureInterruption(
                message: "다른 앱이 카메라를 쓰고 있어 멈췄습니다",
                endsRecording: true,
                needsRestart: true
            )

        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return CaptureInterruption(
                message: "화면 분할 중에는 촬영할 수 없습니다",
                endsRecording: true,
                needsRestart: true
            )

        case .videoDeviceNotAvailableDueToSystemPressure:
            // 발열·배터리로 시스템이 내렸다. 사용자가 할 수 있는 것이 있다.
            return CaptureInterruption(
                message: "기기가 뜨거워 촬영을 멈췄습니다 — 식으면 다시 시작됩니다",
                endsRecording: true,
                needsRestart: true
            )

        case .audioDeviceInUseByAnotherClient:
            // 영상은 계속 들어온다. 끊을 이유가 없다.
            return CaptureInterruption(
                message: "다른 앱이 마이크를 쓰고 있습니다",
                endsRecording: false,
                needsRestart: false
            )

        case .sensitiveContentMitigationActivated:
            return CaptureInterruption(
                message: "시스템이 촬영을 차단했습니다",
                endsRecording: true,
                needsRestart: true
            )

        default:
            // 사유를 모르는 중단. **카메라를 잃었다고 가정한다** — 틀렸다면
            // 녹화 하나를 일찍 끝낸 것이고, 반대로 가정했다가 틀리면 파일과
            // 세션이 둘 다 망가진다. 대가가 다르다.
            return CaptureInterruption(
                message: "촬영이 중단됐습니다",
                endsRecording: true,
                needsRestart: true
            )
        }
    }
}
