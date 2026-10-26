import AVFoundation
import Foundation
import Testing
@testable import Presentation

/// 전화·타앱 선점 같은 중단은 **실기기에서만** 벌어진다. 사유 → 조치의
/// 대응을 값으로 떼어 놓은 덕에 전수로 확인할 수 있다.
@Suite("세션 중단 판정")
struct CaptureInterruptionTests {

    /// 카메라를 잃는 중단은 녹화를 끝내야 한다. 파일을 마무리하지 않으면
    /// 재생할 수 없는 조각이 남고, 세션도 닫히지 않아 클립이 통째로 사라진다.
    @Test("카메라를 잃는 중단은 녹화를 끝내고 재개 때 분석을 다시 세운다")
    func 카메라_상실() {
        let reasons: [AVCaptureSession.InterruptionReason] = [
            .videoDeviceNotAvailableInBackground,
            .videoDeviceInUseByAnotherClient,
            .videoDeviceNotAvailableWithMultipleForegroundApps,
            .videoDeviceNotAvailableDueToSystemPressure,
        ]
        for reason in reasons {
            let plan = CaptureInterruption.make(reason: reason)
            #expect(plan.endsRecording, "\(reason)에서 녹화를 끊지 않으면 파일이 망가진다")
            #expect(plan.needsRestart, "\(reason) 뒤에 분석을 세우지 않으면 영구히 죽는다")
            #expect(plan.message.isEmpty == false)
        }
    }

    /// 영상은 계속 들어온다. 끊을 이유가 없다.
    @Test("마이크만 빼앗긴 중단은 녹화를 끊지 않는다")
    func 마이크만() {
        let plan = CaptureInterruption.make(reason: .audioDeviceInUseByAnotherClient)
        #expect(plan.endsRecording == false)
        #expect(plan.needsRestart == false)
        #expect(plan.message.contains("마이크"))
    }

    @Test("시스템 차단도 카메라를 잃은 것으로 다룬다")
    func 시스템_차단() {
        let plan = CaptureInterruption.make(reason: .sensitiveContentMitigationActivated)
        #expect(plan.endsRecording)
        #expect(plan.needsRestart)
    }

    /// 틀렸다면 녹화 하나를 일찍 끝낸 것이고, 반대로 가정했다가 틀리면
    /// 파일과 세션이 둘 다 망가진다. 대가가 다르다.
    @Test("사유를 모르면 카메라를 잃었다고 가정한다")
    func 사유_불명() {
        let plan = CaptureInterruption.make(reason: nil)
        #expect(plan.endsRecording)
        #expect(plan.needsRestart)
        #expect(plan.message.isEmpty == false)
    }

    @Test("발열 중단은 사용자가 할 수 있는 것을 알려준다")
    func 발열_안내() {
        let plan = CaptureInterruption.make(reason: .videoDeviceNotAvailableDueToSystemPressure)
        #expect(plan.message.contains("뜨거"))
    }

    /// 사유마다 다른 말을 해야 한다. 같은 문구면 왜 멈췄는지 알 수 없다.
    @Test("모든 사유가 서로 다른 안내를 낸다")
    func 안내_구분() {
        let reasons: [AVCaptureSession.InterruptionReason] = [
            .videoDeviceNotAvailableInBackground,
            .audioDeviceInUseByAnotherClient,
            .videoDeviceInUseByAnotherClient,
            .videoDeviceNotAvailableWithMultipleForegroundApps,
            .videoDeviceNotAvailableDueToSystemPressure,
            .sensitiveContentMitigationActivated,
        ]
        let messages = reasons.map { CaptureInterruption.make(reason: $0).message }
        #expect(Set(messages).count == messages.count)
    }
}
