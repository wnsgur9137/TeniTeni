import AVFoundation
import Foundation

/// 시스템 압력 한 단계에 대한 조치.
///
/// ## 왜 값으로 빼는가
///
/// 압력은 **시뮬레이터에 존재하지 않는다.** 판단을 `CameraController` 안에
/// 두면 영원히 검증되지 않고, 실기기에서 처음 도는 코드가 된다. 수준 →
/// 조치의 대응만 떼어 놓으면 전수로 확인할 수 있다 — `CaptureInterruption`과
/// 같은 수법이다.
///
/// ## 왜 직전 조치를 입력으로 받는가
///
/// 조치는 **현재 수준만으로 정할 수 없다.** [ADR-0005](../../../../../docs/05-결정/adr/ADR-0005-thermal-auto-adjust.md)가
/// "복귀는 `.fair` 이하에서만"으로 정했으므로, `.critical`에서 내려온
/// `.serious`는 상한을 **유지**해야 하고 처음부터 `.serious`인 경우와 다르게
/// 행동해야 한다. 현재 수준만 보면 120 ↔ 60을 왕복한다.
///
/// ## 묻지 않는다
///
/// 전에는 `.serious`에서 "120fps를 60fps로 낮출까요"를 제안하도록 적혀
/// 있었다. 압력이 과도해지면 **캡처 시스템이 세션을 스스로 종료하므로**
/// 답을 기다리는 사이에 그게 벌어지고, 사용자는 **6m 밖 코트에 있어**
/// 답할 수도 없다.
struct SystemPressureResponse: Equatable, Sendable {

    /// 분석 목표 fps. 데시메이션 간격이 여기서 나온다.
    ///
    /// 포즈를 덜 돌리는 것이 열을 낮추는 첫 수단이다 — 촬영 fps를 건드리면
    /// 영상 품질이 떨어지지만 이것은 **분석 밀도만** 줄인다.
    let analysisFPS: Double

    /// 촬영 fps 상한. `nil`이면 사용자가 고른 값을 그대로 쓴다.
    let captureFPSCeiling: Double?

    /// 세션을 중단 경로로 넘겨야 하는가. `.shutdown`에서만 참이다.
    let isTerminal: Bool

    static let normal = SystemPressureResponse(
        analysisFPS: 60, captureFPSCeiling: nil, isTerminal: false
    )

    /// - Parameter previous: 직전에 **적용된** 조치. 히스테리시스가 여기서 나온다.
    static func make(
        for level: AVCaptureDevice.SystemPressureState.Level,
        previous: SystemPressureResponse = .normal
    ) -> SystemPressureResponse {
        switch level {
        case .nominal, .fair:
            // 여기서만 상한을 푼다. 올라갈 때와 내려올 때의 문턱이 다르다.
            return .normal

        case .serious:
            // 포즈를 절반으로 줄인다. 촬영은 **새로 건드리지 않되**, 이미
            // 걸린 상한은 유지한다 — 안 그러면 `.critical`에서 내려오자마자
            // 120으로 되돌아가 다시 뜨거워진다.
            return SystemPressureResponse(
                analysisFPS: 30,
                captureFPSCeiling: previous.captureFPSCeiling,
                isTerminal: false
            )

        case .critical:
            // 분석만으로는 모자랐다. 촬영 fps를 내린다 — 묻지 않고 내린 뒤 알린다.
            return SystemPressureResponse(
                analysisFPS: 30, captureFPSCeiling: 60, isTerminal: false
            )

        case .shutdown:
            // 시스템이 세션을 내린다. 중단 경로가 받는다.
            return SystemPressureResponse(
                analysisFPS: 30, captureFPSCeiling: 60, isTerminal: true
            )

        default:
            // 모르는 수준. **압력이 높다고 가정한다** — 틀렸다면 분석이
            // 조금 거칠어진 것이고, 반대로 가정했다가 틀리면 시스템이
            // 세션을 내린다. 대가가 다르다.
            return SystemPressureResponse(
                analysisFPS: 30, captureFPSCeiling: 60, isTerminal: false
            )
        }
    }

    /// 이 조치로 실제 촬영 fps가 얼마가 되는가.
    func targetFPS(requested: Double) -> Double {
        min(requested, captureFPSCeiling ?? .infinity)
    }

    /// 화면에 띄울 말. `nil`이면 **아무것도 띄우지 않는다.**
    ///
    /// ## 왜 표에서 읽지 않고 계산하는가
    ///
    /// 상한이 걸렸다고 해서 실제로 낮아진 것은 아니다. 120fps를 지원하지
    /// 않는 기기는 이미 60으로 찍고 있으므로 상한 60은 **아무것도 바꾸지
    /// 않는다.** 그때 "60fps로 낮췄습니다"를 띄우면 거짓말이다.
    ///
    /// 그래서 요청값과 비교해 **실제로 낮아질 때만** 말한다.
    func notice(requestedFPS: Double) -> String? {
        if isTerminal { return "기기가 과열돼 촬영을 멈췄습니다" }
        let target = targetFPS(requested: requestedFPS)
        guard target < requestedFPS else { return nil }
        return "\(Int(target))fps로 낮췄습니다 — 식으면 돌아갑니다"
    }
}
