import Foundation
import Testing
@testable import Presentation

@Suite("프레임 데시메이션")
struct FrameDecimatorTests {

    @Test("120fps는 두 장에 한 장만 분석한다")
    func 백이십() {
        #expect(FrameDecimator(captureFPS: 120).stride == 2)
    }

    @Test("240fps는 네 장에 한 장")
    func 이백사십() {
        #expect(FrameDecimator(captureFPS: 240).stride == 4)
    }

    @Test("분석 목표와 같거나 느린 촬영은 전부 분석한다")
    func 느린_촬영() {
        #expect(FrameDecimator(captureFPS: 60).stride == 1)
        #expect(FrameDecimator(captureFPS: 30).stride == 1)
    }

    /// 포맷을 못 읽으면 `actualFPS`가 0이다. 그때 0으로 나누면 안 된다.
    @Test("fps가 0이면 전부 분석한다")
    func fps_없음() {
        #expect(FrameDecimator(captureFPS: 0).stride == 1)
        #expect(FrameDecimator(captureFPS: -1).stride == 1)
    }

    @Test("간격이 목표를 넘기지 않도록 내림한다")
    func 내림() {
        // 90 / 60 = 1.5 → 1. 올리면 45fps로 떨어져 목표보다 느려진다.
        #expect(FrameDecimator(captureFPS: 90).stride == 1)
    }

    @Test("stride 2는 짝수 번째만 통과시킨다")
    func 통과_번호() {
        let decimator = FrameDecimator(stride: 2)
        #expect(decimator.includes(0))
        #expect(!decimator.includes(1))
        #expect(decimator.includes(2))
        #expect(!decimator.includes(3))
    }

    @Test("stride 1은 전부 통과시킨다")
    func 전부_통과() {
        let decimator = FrameDecimator(stride: 1)
        #expect((0..<5).allSatisfy { decimator.includes(UInt64($0)) })
    }

    @Test("0이나 음수 간격은 1로 올린다 — 나머지 연산이 터진다")
    func 간격_보호() {
        #expect(FrameDecimator(stride: 0).stride == 1)
        #expect(FrameDecimator(stride: -3).stride == 1)
        #expect(FrameDecimator(stride: 0).includes(7))
    }

    @Test("첫 프레임은 버리지 않는다")
    func 첫_프레임() {
        #expect(FrameDecimator(captureFPS: 120).includes(0))
    }
}
