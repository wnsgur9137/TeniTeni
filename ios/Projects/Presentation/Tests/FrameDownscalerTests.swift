import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import Presentation

/// 합성 픽셀 버퍼. 카메라 없이 전송 경로를 돌린다.
private func makeBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    let status = CVPixelBufferCreate(
        nil, width, height,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        attributes as CFDictionary,
        &buffer
    )
    #expect(status == kCVReturnSuccess)
    return try #require(buffer)
}

@Suite("분석 프레임 다운스케일")
struct FrameDownscalerTests {

    @Test("1080p는 640×360이 된다 — 종횡비 그대로")
    func 가로_1080p() {
        let target = FrameDownscaler().target(for: CMVideoDimensions(width: 1920, height: 1080))
        #expect(target.width == 640)
        #expect(target.height == 360)
    }

    @Test("세로로 선 포맷도 긴 변을 기준으로 줄인다")
    func 세로_포맷() {
        let target = FrameDownscaler().target(for: CMVideoDimensions(width: 1080, height: 1920))
        #expect(target.width == 360)
        #expect(target.height == 640)
    }

    /// 없는 디테일을 만들어도 검출이 좋아지지 않는다.
    @Test("목표보다 작은 원본은 키우지 않는다")
    func 확대_안함() {
        let target = FrameDownscaler().target(for: CMVideoDimensions(width: 320, height: 240))
        #expect(target.width == 320)
        #expect(target.height == 240)
    }

    @Test("두 변을 짝수로 맞춘다 — 4:2:0은 홀수를 좋아하지 않는다")
    func 짝수_정렬() {
        let target = FrameDownscaler().target(for: CMVideoDimensions(width: 1281, height: 721))
        #expect(target.width % 2 == 0)
        #expect(target.height % 2 == 0)
        // 721 * (640/1281) = 360.2 → 360
        #expect(target.width == 640)
        #expect(target.height == 360)
    }

    @Test("크기를 못 읽으면 원본을 그대로 돌려준다")
    func 빈_크기() {
        let target = FrameDownscaler().target(for: CMVideoDimensions(width: 0, height: 0))
        #expect(target.width == 0)
        #expect(target.height == 0)
    }

    @Test("긴 변 상한을 바꾸면 목표도 바뀐다")
    func 상한_변경() {
        let target = FrameDownscaler(longEdge: 320).target(for: CMVideoDimensions(width: 1920, height: 1080))
        #expect(target.width == 320)
        #expect(target.height == 180)
    }

    @Test("목적지 버퍼가 목표 크기로 나온다")
    func 목적지_크기() throws {
        let downscaler = FrameDownscaler()
        let destination = try downscaler.makeDestination(for: CMVideoDimensions(width: 1920, height: 1080))
        #expect(CVPixelBufferGetWidth(destination) == 640)
        #expect(CVPixelBufferGetHeight(destination) == 360)
    }

    @Test("원본 크기가 바뀌면 풀을 다시 세운다")
    func 크기_변경() throws {
        let downscaler = FrameDownscaler()
        let first = try downscaler.makeDestination(for: CMVideoDimensions(width: 1920, height: 1080))
        let second = try downscaler.makeDestination(for: CMVideoDimensions(width: 1280, height: 960))
        #expect(CVPixelBufferGetWidth(first) == 640)
        #expect(CVPixelBufferGetHeight(first) == 360)
        #expect(CVPixelBufferGetWidth(second) == 640)
        #expect(CVPixelBufferGetHeight(second) == 480)
    }

    @Test("크기가 0이면 목적지를 만들지 않는다")
    func 목적지_거부() {
        #expect(throws: FrameDownscaler.Failure.emptyDimensions) {
            try FrameDownscaler().makeDestination(for: CMVideoDimensions(width: 0, height: 0))
        }
    }

    @Test("원본을 목적지로 전송한다")
    func 전송() throws {
        let downscaler = FrameDownscaler()
        let source = try makeBuffer(width: 1920, height: 1080)
        let destination = try downscaler.makeDestination(for: CMVideoDimensions(width: 1920, height: 1080))
        try downscaler.transfer(from: source, to: destination)
        #expect(CVPixelBufferGetWidth(destination) == 640)
    }

    @Test("같은 다운스케일러로 여러 장을 연달아 전송한다")
    func 연속_전송() throws {
        let downscaler = FrameDownscaler()
        let source = try makeBuffer(width: 1920, height: 1080)
        for _ in 0..<5 {
            let destination = try downscaler.makeDestination(
                for: CMVideoDimensions(width: 1920, height: 1080)
            )
            try downscaler.transfer(from: source, to: destination)
        }
    }
}
