import CoreVideo
import Foundation

/// 클립으로 쓸 한 프레임.
///
/// ## 왜 `CVPixelBuffer`를 프로퍼티로 두지 않는가
///
/// `CVPixelBuffer`는 `CVBuffer`의 별칭이고 그것은 **class이며 Sendable이
/// 아니다.** `SWIFT_STRICT_CONCURRENCY=complete`에서 Sendable 타입의
/// 저장 프로퍼티로 두면 컴파일이 거부된다. 링 버퍼는 Sendable만 담으므로
/// 프로퍼티로 두는 길은 애초에 막혀 있다.
///
/// 픽셀에 닿는 것은 쓰기 직전 한 번뿐이다. 그래서 빌려주는 형태로 받는다 —
/// `CMReadySampleBuffer.withUnsafeSampleBuffer(_:)`와 같은 모양이다.
///
/// ## 왜 `CMReadySampleBuffer`를 직접 쓰지 않는가
///
/// 그 타입은 **iOS 26 / macOS 26 이상**이다. `TeniVision`은 macOS 15도
/// 지원한다(`TeniTool`이 같은 프레임워크를 정적 링크한다). 직접 쓰면
/// macOS 빌드가 깨지고, `@available`로 가리면 macOS에서 테스트가 조용히
/// 건너뛰어진다. 카메라 경계(iOS 전용)에서 이 프로토콜에 적합시킨다.
///
/// 근거: docs/07-기획/SPEC-0091-swing-clip-recording.md 구현 선택지 1
public protocol ClipFrame: Sendable {
    /// 세션 시계 기준 프레임 시각. **트리거가 쓰는 시계와 같아야 한다** —
    /// 다르면 구간이 조용히 어긋난다.
    var seconds: TimeInterval { get }

    /// 픽셀 버퍼를 빌려준다.
    ///
    /// `Result`를 `Sendable`로 묶었다. `CVPixelBuffer`가 Sendable이 아니므로
    /// **버퍼를 그대로 돌려주는 코드가 컴파일되지 않는다** — "빌려준다"는
    /// 말이 주석이 아니라 타입으로 강제된다.
    func withPixelBuffer<Result: Sendable>(
        _ body: (CVPixelBuffer) throws -> Result
    ) rethrows -> Result
}
