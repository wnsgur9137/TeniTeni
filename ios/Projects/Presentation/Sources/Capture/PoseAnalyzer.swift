import CoreMedia
import Foundation
import ImageIO
import Synchronization
import TeniVision

/// 프레임 한 장의 포즈 결과.
enum PoseOutcome: Sendable, Equatable {
    case detected(PoseFrame)
    /// 사람이 안 보인다. 오류가 아니다 — 코트에 아직 아무도 없을 수 있다.
    case notFound
    case failed(String)
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
/// 쌓아 두면 지연이 누적돼 트리거가 과거를 보고 울린다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
final class PoseAnalyzer: Sendable {

    private let stream: AsyncStream<ReadyFrame>
    private let continuation: AsyncStream<ReadyFrame>.Continuation
    private let estimator: PoseEstimator
    /// 버퍼가 세워진 방향. 회전은 메인에서 바뀌고 분석 Task에서 읽힌다.
    private let orientation: Mutex<CGImagePropertyOrientation?>

    init(estimator: PoseEstimator = PoseEstimator()) {
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
    func run(onOutcome: @Sendable (PoseOutcome) -> Void) async {
        let downscaler = FrameDownscaler()

        for await frame in stream {
            do {
                // 목적지를 빌림 **밖에서** 만든다. 이 버퍼는 우리 것이라
                // `await`를 넘어가도 살아 있다 — 빌린 원본은 그럴 수 없다.
                let destination = try downscaler.makeDestination(for: frame.dimensions)
                try frame.withPixelBuffer { source in
                    try downscaler.transfer(from: source, to: destination)
                }

                let pose = try await estimator.frame(
                    in: destination,
                    at: frame.seconds,
                    orientation: orientation.withLock { $0 }
                )
                onOutcome(pose.map(PoseOutcome.detected) ?? .notFound)
            } catch is CancellationError {
                return
            } catch {
                onOutcome(.failed(error.localizedDescription))
            }
        }
    }
}
