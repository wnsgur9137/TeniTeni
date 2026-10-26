import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Synchronization
import TeniVision
import Testing
@testable import Presentation

/// 카메라 없이 만드는 프레임.
///
/// `CMReadySampleBuffer`는 픽셀 버퍼와 포맷·시각으로 직접 만들 수 있다
/// (`init(pixelBuffer:formatDescription:presentationTimeStamp:duration:)`).
/// 덕분에 인테이크 이후의 경로는 전부 합성 입력으로 돌릴 수 있다.
func makeReadyFrame(
    seconds: Double,
    width: Int = 1920,
    height: Int = 1080
) throws -> ReadyFrame {
    var pixel: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        nil, width, height,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
        &pixel
    )
    #expect(status == kCVReturnSuccess)
    let buffer = try #require(pixel)

    var format: CMFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format
    )
    #expect(formatStatus == noErr)
    // 호출 인자 안에서 풀면 `#require`의 문맥 타입이 옵셔널이 되어
    // "nil이 될 수 없다"는 경고가 붙는다. 밖에서 푼다.
    let description = try #require(format)

    let ready = CMReadySampleBuffer(
        pixelBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: buffer),
        formatDescription: description,
        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
        duration: .invalid
    )
    return ReadyFrame(ready)
}

/// 정해진 답만 돌려주는 추정기. Vision은 시뮬레이터에서 돌지 않으므로
/// (컴퓨트 디바이스 없음) 이것이 없으면 `.detected` 이후의 코드가 전부
/// 미검증으로 남는다.
struct StubEstimator: PoseEstimating {
    let answers: [PoseReading]
    /// 몇 번째 호출에 어떤 답을 줄지. 답이 떨어지면 마지막 답을 반복한다.
    private let calls = Counter()

    init(_ answers: [PoseReading]) {
        self.answers = answers
    }

    var callCount: Int { calls.value }

    func reading(
        in pixelBuffer: CVPixelBuffer,
        at timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation?
    ) async throws -> PoseReading {
        let index = calls.next()
        guard !answers.isEmpty else { return .noPerson }
        let answer = answers[min(index, answers.count - 1)]
        // 포즈는 호출 시각을 달고 나가야 한다 — 그 시계가 트리거와 같아야 한다.
        if case .pose(let frame) = answer {
            return .pose(PoseFrame(timestamp: timestamp, joints: frame.joints))
        }
        return answer
    }
}

/// 항상 던지는 추정기.
struct FailingEstimator: PoseEstimating {
    struct Boom: Error {}

    func reading(
        in pixelBuffer: CVPixelBuffer,
        at timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation?
    ) async throws -> PoseReading {
        throw Boom()
    }
}

/// 호출 횟수를 세는 함. 추정기가 `Sendable`이어야 하므로 잠금을 쓴다 —
/// `@unchecked Sendable`은 쓰지 않는다(동시성 6.1의 4항).
final class Counter: Sendable {
    private let storage = Mutex(0)

    var value: Int { storage.withLock { $0 } }

    /// 올리기 **전** 값을 돌려준다.
    func next() -> Int {
        storage.withLock { current in
            defer { current += 1 }
            return current
        }
    }
}
