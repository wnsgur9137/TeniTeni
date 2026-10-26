import CoreMedia
import Foundation
import ImageIO
import Synchronization
import TeniVision

/// 프레임 한 장의 포즈 결과.
///
/// **모든 경우가 프레임 시각을 들고 있다.** 들고 있지 않으면 화면이 "언제
/// 끊겼는가"를 벽시계로 재게 되고, 그 둘은 다른 축이다 — 메인 액터가
/// 300ms 막히면 프레임 간격이 8ms였는데도 "끊겼다"고 판정한다.
enum PoseOutcome: Sendable, Equatable {
    case detected(PoseFrame)
    /// 사람이 안 보인다. 오류가 아니다 — 코트에 아직 아무도 없을 수 있다.
    case noPerson(at: TimeInterval)
    /// 사람은 보이는데 어깨를 믿을 수 없다.
    case unusable(at: TimeInterval)
    case failed(String, at: TimeInterval)

    /// 결과가 가리키는 프레임 시각. 전부 같은 시계(샘플의 PTS)다.
    var seconds: TimeInterval {
        switch self {
        case .detected(let frame): frame.timestamp
        case .noPerson(let at), .unusable(let at): at
        case .failed(_, let at): at
        }
    }
}

/// 프레임을 포즈로 바꾸는 **단일 Task**.
///
/// ## 왜 actor가 아닌가
///
/// [동시성 6.1](../../../../../docs/02-설계/CONCURRENCY.md)이 "순서가 중요한
/// 처리는 actor가 아니라 단일 Task"로 정했다. 트리거는 프레임 순서에 의존하는
/// 상태 기계이므로, 순서가 코드 구조로 보장돼야 한다.
///
/// ## 왜 bufferingNewest(1)인가
///
/// 포즈는 최신성이 우선이다. 밀린 프레임의 포즈는 이미 지난 자세다 —
/// 쌓아 두면 지연이 누적돼 트리거가 과거를 보고 울린다. 버퍼를 1로 묶는
/// 것은 캡처 풀 점유를 1장으로 묶는 뜻도 된다(`FrameIntake` 참조).
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
final class PoseAnalyzer: Sendable {

    private let stream: AsyncStream<ReadyFrame>
    private let continuation: AsyncStream<ReadyFrame>.Continuation
    private let estimator: any PoseEstimating
    /// 버퍼가 세워진 방향. 회전은 메인에서 바뀌고 분석 Task에서 읽힌다.
    private let orientation: Mutex<CGImagePropertyOrientation?>

    init(estimator: any PoseEstimating = PoseEstimator()) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ReadyFrame.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.stream = stream
        self.continuation = continuation
        self.estimator = estimator
        self.orientation = Mutex(nil)
    }

    /// 캡처 큐에서 호출한다. 즉시 반환한다.
    func submit(_ frame: ReadyFrame) {
        continuation.yield(frame)
    }

    func finish() {
        continuation.finish()
    }

    func update(orientation new: CGImagePropertyOrientation?) {
        orientation.withLock { $0 = new }
    }

    /// 스트림이 끝날 때까지 돈다. **한 번만** 호출한다 — 둘이 돌면 순서가 깨진다.
    ///
    /// 처리를 `async`로 받는다. 그래야 `actor ClipRecorder`를 **이 루프 안에서
    /// 한 장씩 끝까지** `await`할 수 있다 — 콜백에서 `Task`를 띄우면 비구조
    /// Task가 생성 순서대로 실행되지 않아 트리거의 순서가 깨진다.
    /// 프레임도 함께 넘긴다. 클립에 쓸 픽셀은 포즈가 아니라 프레임에 있다.
    func run(onOutcome: @Sendable (ReadyFrame, PoseOutcome) async -> Void) async {
        let downscaler = FrameDownscaler()

        for await frame in stream {
            let seconds = frame.seconds
            do {
                // 목적지를 빌림 **밖에서** 만든다. 이 버퍼는 우리 것이라
                // `await`를 넘어가도 살아 있다 — 빌린 원본은 그럴 수 없다.
                let destination = try downscaler.makeDestination(for: frame.dimensions)
                try frame.withPixelBuffer { source in
                    try downscaler.transfer(from: source, to: destination)
                }

                let reading = try await estimator.reading(
                    in: destination,
                    at: seconds,
                    orientation: orientation.withLock { $0 }
                )
                switch reading {
                case .pose(let pose): await onOutcome(frame, .detected(pose))
                case .noPerson: await onOutcome(frame, .noPerson(at: seconds))
                case .unusable: await onOutcome(frame, .unusable(at: seconds))
                }
            } catch is CancellationError {
                return
            } catch {
                await onOutcome(frame, .failed(error.localizedDescription, at: seconds))
            }
        }
    }
}
