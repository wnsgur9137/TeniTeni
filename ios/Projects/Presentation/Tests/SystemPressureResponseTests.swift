import AVFoundation
import Foundation
import Testing
@testable import Presentation

/// 시스템 압력은 **시뮬레이터에 존재하지 않는다.** 판단을 값으로 떼어
/// 놓은 덕에 전수로 확인할 수 있다.
@Suite("시스템 압력 대응")
struct SystemPressureResponseTests {

    @Test("압력이 없으면 아무것도 하지 않는다")
    func 정상() {
        for level in [AVCaptureDevice.SystemPressureState.Level.nominal, .fair] {
            let response = SystemPressureResponse.make(for: level)
            #expect(response == .normal)
            #expect(response.notice == nil, "\(level)에서 화면을 건드리면 안 된다")
            #expect(response.captureFPSCeiling == nil)
            #expect(response.analysisFPS == 60)
        }
    }

    /// 포즈를 덜 돌리는 것이 열을 낮추는 첫 수단이다. 촬영을 건드리면
    /// 영상 품질이 떨어지지만 이것은 분석 밀도만 줄인다.
    @Test("serious는 분석만 줄이고 촬영은 건드리지 않는다")
    func 심각() {
        let response = SystemPressureResponse.make(for: .serious)
        #expect(response.analysisFPS == 30)
        #expect(response.captureFPSCeiling == nil, "촬영 fps를 아직 내리지 않는다")
        #expect(response.isTerminal == false)
    }

    /// 조용히 조정하는 것이 의도다. 6m 밖 사용자를 방해하지 않는다 —
    /// 그 사실은 클립의 fps와 드롭 카운터로 드러난다.
    @Test("serious에서는 화면에 아무것도 띄우지 않는다")
    func 심각_무고지() {
        #expect(SystemPressureResponse.make(for: .serious).notice == nil)
    }

    /// 묻지 않고 내린 뒤 알린다 — ADR-0005.
    @Test("critical은 촬영 fps를 내리고 사후에 알린다")
    func 치명적() throws {
        let response = SystemPressureResponse.make(for: .critical)
        #expect(response.captureFPSCeiling == 60)
        #expect(response.analysisFPS == 30)
        let notice = try #require(response.notice)
        #expect(notice.contains("60fps"), "무엇이 바뀌었는지 말해야 한다")
        #expect(response.isTerminal == false, "아직 멈추지는 않는다")
    }

    @Test("shutdown은 중단 경로로 넘긴다")
    func 종료() {
        let response = SystemPressureResponse.make(for: .shutdown)
        #expect(response.isTerminal)
        #expect(response.notice != nil)
    }

    /// 틀렸다면 분석이 조금 거칠어진 것이고, 반대로 가정했다가 틀리면
    /// 시스템이 세션을 내린다. 대가가 다르다.
    @Test("모르는 수준은 압력이 높다고 가정한다")
    func 미지_수준() {
        let response = SystemPressureResponse.make(
            for: AVCaptureDevice.SystemPressureState.Level(rawValue: "방금 생긴 수준")
        )
        #expect(response.analysisFPS == 30)
        #expect(response.captureFPSCeiling == 60)
        #expect(response.isTerminal == false, "모른다고 촬영을 끊지는 않는다")
    }

    /// 수준이 올라갈수록 분석이 촘촘해지면 안 된다.
    @Test("압력이 높아질수록 분석 밀도가 낮아지거나 유지된다")
    func 단조성() {
        let ordered: [AVCaptureDevice.SystemPressureState.Level] =
            [.nominal, .fair, .serious, .critical, .shutdown]
        let densities = ordered.map { SystemPressureResponse.make(for: $0).analysisFPS }
        #expect(zip(densities, densities.dropFirst()).allSatisfy { $0 >= $1 })
    }
}
