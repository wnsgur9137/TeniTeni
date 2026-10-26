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
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
final class FrameIntake: NSObject, Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// 데시메이션을 통과한 프레임만. 포즈가 받는다.
    ///
    /// `ReadyFrame` 한 장은 **캡처 풀 버퍼 한 장을 점유한다**(아래 사본
    /// 주석 참조). 받는 쪽이 여러 장을 쌓아 두면 풀이 마르고 드롭이 시작된다.
    /// 지금은 `bufferingNewest(1)`이 1장으로 묶는다. 전 프레임을 링 버퍼에
    /// 담는 경로([#97](https://github.com/wnsgur9137/TeniTeni/issues/97))를
    /// 붙일 때는 **상한을 명시적으로 걸어야 한다.**
    private let onAnalysisFrame: @Sendable (ReadyFrame) -> Void

    private let sequence = Atomic<UInt64>(0)
    /// 포맷이 바뀌면 간격도 바뀐다. 캡처 큐에서 읽고 메인에서 쓴다.
    private let decimator: Mutex<FrameDecimator>

    /// AVFoundation이 버린 프레임 수.
    ///
    /// `alwaysDiscardsLateVideoFrames = true`라 밀린 프레임은 **조용히**
    /// 사라진다. 기획서가 프레임 드롭을 최상위 리스크로 올려놓고 실측을
    /// 실기기로 넘겼는데, 세는 자리가 없으면 실측할 수단이 없다 —
    /// 포즈가 예산을 넘겨 절반이 드롭돼도 화면에는 "사람이 보입니다"가
    /// 계속 떠 있다.
    private let dropped = Atomic<UInt64>(0)

    /// 내용이 픽셀 버퍼가 아니어서 버린 프레임 수.
    private let rejected = Atomic<UInt64>(0)

    init(
        decimator: FrameDecimator = FrameDecimator(stride: 1),
        onAnalysisFrame: @escaping @Sendable (ReadyFrame) -> Void
    ) {
        self.decimator = Mutex(decimator)
        self.onAnalysisFrame = onAnalysisFrame
        super.init()
    }

    /// 촬영 fps가 정해지거나 바뀔 때 호출한다.
    func update(decimator new: FrameDecimator) {
        decimator.withLock { $0 = new }
    }

    var droppedCount: UInt64 { dropped.load(ordering: .relaxed) }
    var rejectedCount: UInt64 { rejected.load(ordering: .relaxed) }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 델리게이트 인자는 AVFoundation의 것이다. `init(unsafeBuffer:)`가
        // `sending`을 요구하므로 **사본**을 만들어 넘긴다.
        //
        // 이 복사는 **얕다.** `CVImageBuffer`는 참조로 따라오므로 픽셀은
        // 복사되지 않고, 그 대신 **사본이 참조를 붙들고 있는 동안 그
        // IOSurface는 캡처 풀로 돌아가지 못한다.** 즉 `ReadyFrame` 한 장 =
        // 캡처 풀 버퍼 한 장 점유다. 공짜가 아니다.
        var copied: CMSampleBuffer?
        let status = CMSampleBufferCreateCopy(
            allocator: nil, sampleBuffer: sampleBuffer, sampleBufferOut: &copied
        )
        guard status == noErr, let copied else {
            rejected.wrappingAdd(1, ordering: .relaxed)
            return
        }

        // AVFoundation의 델리게이트 인자는 `sending`으로 선언돼 있지 않다
        // (SDK 헤더: `- (void)captureOutput:didOutputSampleBuffer:fromConnection:`).
        // 사본을 만들어도 "입력에서 파생됐다"는 사실이 남아 영역 검사를
        // 통과하지 못한다. 검사를 끊는 것은 **이 한 줄뿐**이고, 끊어도 되는
        // 근거는 전달 후 AVFoundation도 이 함수도 그 픽셀을 다시 쓰지 않고,
        // 사본의 참조가 IOSurface를 살려 둔다는 것이다.
        nonisolated(unsafe) let transferred = copied

        // `init(unsafeWithPixelBuffer:)`는 실패 가능 생성자가 **아니고**
        // 내용을 검사하지 않는다. 샘플에 이미지 버퍼가 없으면 잘못된
        // `ReadyFrame`이 만들어져 분석 Task 깊은 곳에서 터진다 — 원인과
        // 먼 자리다. 동적 내용으로 감싼 뒤 실패 가능 다운캐스트로 걸러낸다.
        let dynamic = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: transferred)
        guard let ready = CMReadySampleBuffer<CVReadOnlyPixelBuffer>(dynamic) else {
            rejected.wrappingAdd(1, ordering: .relaxed)
            return
        }

        intake(ReadyFrame(ready))
    }

    /// 밀려서 버려진 프레임. 세기만 한다 — 콜백에서 할 일이 아니다.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dropped.wrappingAdd(1, ordering: .relaxed)
    }

    /// 세고, 거르고, 넘긴다. **카메라 없이 호출할 수 있는 자리**로 빼 뒀다 —
    /// 번호 매김과 데시메이터의 결합(0번 프레임을 살리는 off-by-one)은
    /// `captureOutput` 안에 두면 검증할 방법이 없다.
    func intake(_ frame: ReadyFrame) {
        // 번호를 먼저 올리고 **올리기 전 값**을 쓴다. 0번 프레임이 분석에
        // 들어가야 첫 장을 버리지 않는다.
        let index = sequence.wrappingAdd(1, ordering: .relaxed).oldValue
        guard decimator.withLock({ $0.includes(index) }) else { return }
        onAnalysisFrame(frame)
    }
}
