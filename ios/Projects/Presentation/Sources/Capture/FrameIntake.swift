import AVFoundation
import CoreMedia
import Foundation
import Synchronization

/// 카메라 콜백이 들어오는 자리.
///
/// **콜백은 즉시 반환한다.** 여기서 무거운 일을 하면 캡처 풀이 고갈돼 프레임이
/// 드롭된다 — [동시성 6.1](../../../../../docs/02-설계/CONCURRENCY.md) 2항.
/// 하는 일은 셋뿐이다: 감싸고, 셈하고, 넘긴다.
///
/// 분석 대상과 전 프레임 경로를 나눠 내보낸다. 지금은 분석(포즈)만 쓰고,
/// 전 프레임은 [#97](https://github.com/wnsgur9137/TeniTeni/issues/97)에서
/// `ClipRecorder`가 받는다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
final class FrameIntake: NSObject, Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// 모든 프레임. 녹화 링 버퍼가 받을 자리다.
    private let onFrame: (@Sendable (ReadyFrame) -> Void)?
    /// 데시메이션을 통과한 프레임만. 포즈가 받는다.
    private let onAnalysisFrame: @Sendable (ReadyFrame) -> Void

    private let sequence = Atomic<UInt64>(0)
    /// 포맷이 바뀌면 간격도 바뀐다. 캡처 큐에서 읽고 메인에서 쓴다.
    private let decimator: Mutex<FrameDecimator>

    init(
        decimator: FrameDecimator = FrameDecimator(stride: 1),
        onFrame: (@Sendable (ReadyFrame) -> Void)? = nil,
        onAnalysisFrame: @escaping @Sendable (ReadyFrame) -> Void
    ) {
        self.decimator = Mutex(decimator)
        self.onFrame = onFrame
        self.onAnalysisFrame = onAnalysisFrame
        super.init()
    }

    /// 촬영 fps가 정해지거나 바뀔 때 호출한다.
    func update(decimator new: FrameDecimator) {
        decimator.withLock { $0 = new }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 델리게이트 인자는 AVFoundation의 것이다. `init(unsafeWithPixelBuffer:)`가
        // `sending`을 요구하므로 **우리 것인 사본**을 만들어 넘긴다. 픽셀은
        // 복사되지 않는다 — 이미지 버퍼는 참조로 따라온다.
        var copied: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(
            allocator: nil, sampleBuffer: sampleBuffer, sampleBufferOut: &copied
        )
        guard status == noErr, let copied else { return }

        // AVFoundation의 델리게이트 인자는 `sending`으로 선언돼 있지 않다
        // (SDK 헤더: `- (void)captureOutput:didOutputSampleBuffer:fromConnection:`).
        // 그래서 영역 검사는 위의 사본까지 "호출자와 같은 영역"으로 본다 —
        // 사본을 만들어도 입력에서 파생됐다는 사실이 남기 때문이다.
        //
        // 검사를 끊는 것은 **이 한 줄뿐**이고, 끊어도 되는 근거는 위의 복사다.
        // AVFoundation은 호출이 끝나면 원본을 풀에 되돌리지만 사본은 우리
        // 것이고, 이 함수는 사본을 다시 쓰지 않는다.
        nonisolated(unsafe) let transferred = copied
        let ready = CMReadySampleBuffer<CVReadOnlyPixelBuffer>(unsafeWithPixelBuffer: transferred)
        let frame = ReadyFrame(ready)

        onFrame?(frame)

        // 번호를 먼저 올린다. 0번 프레임이 분석에 들어가야 첫 장을 버리지 않는다.
        let index = sequence.wrappingAdd(1, ordering: .relaxed).oldValue
        guard decimator.withLock({ $0.includes(index) }) else { return }
        onAnalysisFrame(frame)
    }
}
