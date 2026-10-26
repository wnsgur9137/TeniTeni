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
            #expect(response.notice(requestedFPS: 120) == nil, "\(level)에서 화면을 건드리면 안 된다")
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
        #expect(SystemPressureResponse.make(for: .serious).notice(requestedFPS: 120) == nil)
    }

    /// 묻지 않고 내린 뒤 알린다 — ADR-0005.
    @Test("critical은 촬영 fps를 내리고 사후에 알린다")
    func 치명적() throws {
        let response = SystemPressureResponse.make(for: .critical)
        #expect(response.captureFPSCeiling == 60)
        #expect(response.analysisFPS == 30)
        let notice = try #require(response.notice(requestedFPS: 120))
        #expect(notice.contains("60fps"), "무엇이 바뀌었는지 말해야 한다")
        #expect(response.isTerminal == false, "아직 멈추지는 않는다")
    }

    @Test("shutdown은 중단 경로로 넘긴다")
    func 종료() {
        let response = SystemPressureResponse.make(for: .shutdown)
        #expect(response.isTerminal)
        #expect(response.notice(requestedFPS: 120) != nil)
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

    // MARK: - 리뷰가 비어 있다고 지적한 자리

    /// ADR-0005는 "복귀는 `.fair` 이하에서만"으로 정했다. 현재 수준만 보면
    /// `.critical` → `.serious`에서 120으로 되돌아가 다시 뜨거워진다 —
    /// 120 ↔ 60 왕복이다.
    @Test("critical에서 내려온 serious는 상한을 유지한다")
    func 히스테리시스() {
        let critical = SystemPressureResponse.make(for: .critical)
        #expect(critical.captureFPSCeiling == 60)

        let serious = SystemPressureResponse.make(for: .serious, previous: critical)
        #expect(serious.captureFPSCeiling == 60, "상한이 풀리면 바로 다시 뜨거워진다")

        // 처음부터 .serious면 촬영을 건드리지 않는다.
        let fresh = SystemPressureResponse.make(for: .serious)
        #expect(fresh.captureFPSCeiling == nil)
    }

    @Test("fair 이하로 내려가면 상한이 풀린다")
    func 복귀() {
        let critical = SystemPressureResponse.make(for: .critical)
        for level in [AVCaptureDevice.SystemPressureState.Level.fair, .nominal] {
            let recovered = SystemPressureResponse.make(for: level, previous: critical)
            #expect(recovered == .normal, "\(level)에서 원래 설정으로 돌아간다")
            #expect(recovered.notice(requestedFPS: 120) == nil, "돌아갔으면 표시도 내린다")
        }
    }

    /// 120fps를 지원하지 않는 기기는 이미 60으로 찍고 있다. 상한 60은
    /// 아무것도 바꾸지 않으므로 "낮췄습니다"는 거짓말이다.
    @Test("실제로 낮아지지 않으면 말하지 않는다")
    func 거짓_고지_없음() {
        let critical = SystemPressureResponse.make(for: .critical)
        #expect(critical.notice(requestedFPS: 60) == nil, "이미 60인 기기에 낮췄다고 하면 거짓이다")
        #expect(critical.notice(requestedFPS: 120) != nil)
    }

    @Test("목표 fps는 요청값과 상한의 작은 쪽이다")
    func 목표값() {
        #expect(SystemPressureResponse.normal.targetFPS(requested: 120) == 120)
        #expect(SystemPressureResponse.make(for: .critical).targetFPS(requested: 120) == 60)
        #expect(SystemPressureResponse.make(for: .critical).targetFPS(requested: 60) == 60)
        #expect(SystemPressureResponse.make(for: .serious).targetFPS(requested: 120) == 120)
    }

    /// 압력이 높아질수록 촬영 상한이 **느슨해지면** 안 된다.
    @Test("압력이 높아질수록 촬영 상한이 조이거나 유지된다")
    func 상한_단조성() {
        var previous = SystemPressureResponse.normal
        var ceilings: [Double] = []
        for level in [AVCaptureDevice.SystemPressureState.Level.nominal, .fair, .serious, .critical, .shutdown] {
            previous = SystemPressureResponse.make(for: level, previous: previous)
            ceilings.append(previous.captureFPSCeiling ?? .infinity)
        }
        #expect(zip(ceilings, ceilings.dropFirst()).allSatisfy { $0 >= $1 })
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
