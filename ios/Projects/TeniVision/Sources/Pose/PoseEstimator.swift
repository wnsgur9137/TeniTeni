import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// Vision 포즈 요청을 감싼다.
///
/// ## 왜 struct인가
///
/// `DetectHumanBodyPoseRequest`는 `struct`이고 `Sendable`이다. 상태를
/// 누적하는 `StatefulRequest`(궤적 검출)와 달라서 인스턴스를 붙들어 둘
/// 이유가 없다 — [동시성 6.4](../../../../docs/02-설계/CONCURRENCY.md).
///
/// 순서는 호출부의 단일 `Task`가 지킨다. 여기에 actor를 두면 `await`
/// 지점에서 재진입돼 순서 보장이 코드에서 사라진다.
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md
public struct PoseEstimator: Sendable {

    /// 사람을 고를 때 어깨를 믿을지 판단하는 임계. 트리거와 같은 값을 쓴다 —
    /// 트리거가 버릴 관절로 사람을 고르면 고르자마자 신호가 끊긴다.
    public let minimumConfidence: Double

    private let request: DetectHumanBodyPoseRequest

    public init(minimumConfidence: Double = SwingTriggerProfile.default.minimumConfidence) {
        self.minimumConfidence = minimumConfidence
        self.request = DetectHumanBodyPoseRequest()
    }

    /// 프레임 하나에서 포즈를 뽑는다. 사람이 안 보이면 `nil`이다.
    ///
    /// - Parameters:
    ///   - pixelBuffer: **분석용으로 줄인 사본**을 넣는다. 원본을 넣으면
    ///     1080p 추정이 프레임 예산을 넘는다([비전 파이프라인 3.7](../../../../docs/02-설계/VISION-PIPELINE.md)).
    ///   - orientation: 버퍼가 세워진 방향. Vision이 이것을 받아 **좌표까지
    ///     맞춰 돌려준다** — 버퍼를 돌리지 않아도 된다.
    /// `pixelBuffer`를 `sending`으로 받지 않는다. 받으면 호출부가 그 버퍼를
    /// 두 번 쓸 수 없어 — 루프 안에서 다음 프레임을 위해 들고 있는 것조차
    /// "전달 후 사용"이 된다. 이 함수와 호출부는 둘 다 nonisolated이므로
    /// 격리 경계를 넘지 않고, 넘길 것도 없다.
    public func frame(
        in pixelBuffer: CVPixelBuffer,
        at timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> PoseFrame? {
        let observations = try await request.perform(on: pixelBuffer, orientation: orientation)
        guard let chosen = Self.primary(in: observations, minimumConfidence: minimumConfidence) else {
            return nil
        }
        return PoseFrameAdapter.frame(from: chosen, at: timestamp)
    }

    /// 여러 사람이 잡히면 **어깨 폭이 가장 큰 사람**을 고른다.
    ///
    /// 코트에는 상대도 있고 뒤 코트 사람도 있다. 배열 순서는 보장되지 않으므로
    /// 첫 번째를 쓰면 프레임마다 다른 사람을 볼 수 있다. 어깨 폭은 카메라와의
    /// 거리에 반비례하고, 트리거가 이미 기준 길이로 쓰는 값이다.
    ///
    /// 어깨가 전원 안 보이면 **아무도 고르지 않는다.** 그 프레임에서 트리거는
    /// 어차피 몸통선을 못 내므로, 임의로 고르면 다음 프레임에 사람이 바뀔
    /// 위험만 남는다.
    static func primary<Observation: BodyPoseObservable>(
        in observations: [Observation],
        minimumConfidence: Double
    ) -> Observation? {
        observations
            .compactMap { observation -> (Observation, Double)? in
                guard let width = observation.shoulderWidth(minimumConfidence: minimumConfidence)
                else { return nil }
                return (observation, width)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
