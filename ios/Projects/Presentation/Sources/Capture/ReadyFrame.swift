import CoreMedia
import CoreVideo
import Foundation
import TeniVision

/// 캡처 콜백이 받은 샘플을 격리 도메인 밖으로 넘길 수 있게 감싼 프레임.
///
/// `CMSampleBuffer`는 참조 타입이고 `Sendable`이 아니다. `CMReadySampleBuffer`로
/// **경계에서 한 번** 감싸면 이후로는 `@unchecked Sendable` 없이 넘길 수 있다 —
/// [동시성 6.3](../../../../../docs/02-설계/CONCURRENCY.md).
///
/// 이 타입이 `Presentation`에 있는 이유는 `CMReadySampleBuffer`가
/// **iOS 26 / macOS 26 이상**이기 때문이다. `TeniVision`은 macOS 15도
/// 지원하므로 거기에 둘 수 없다. 그래서 엔진은 `ClipFrame` 프로토콜로 받고,
/// 적합시키는 일은 카메라 경계인 여기서 한다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
struct ReadyFrame: ClipFrame {

    private let buffer: CMReadySampleBuffer<CVReadOnlyPixelBuffer>

    init(_ ready: CMReadySampleBuffer<CVReadOnlyPixelBuffer>) {
        self.buffer = ready
    }

    /// 프레임 시계 기준 시각 — 부팅 이후 호스트 시각이다.
    ///
    /// 벽시계가 아니다. 세션으로 옮길 때 원점을 빼야 한다 —
    /// `SessionBuilder`가 그 변환을 들고 있다.
    var seconds: TimeInterval { buffer.presentationTimeStamp.seconds }

    /// 원본 해상도. 분석용 목적지 버퍼를 **빌리기 전에** 만들기 위해 필요하다.
    var dimensions: CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(buffer.formatDescription)
    }

    func withPixelBuffer<Result: Sendable>(
        _ body: (CVPixelBuffer) throws -> Result
    ) rethrows -> Result {
        try buffer.content.withUnsafeBuffer { try body($0) }
    }
}
