import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// 프레임 한 장에서 읽어낸 것.
///
/// ## 왜 `PoseFrame?`이 아닌가
///
/// 옵셔널로 두면 **"사람이 없다"와 "사람은 있는데 쓸 어깨가 없다"가
/// 구분되지 않는다.** 화면이 둘을 "사람이 안 보입니다" 하나로 합치면,
/// 측면으로 서서 한쪽 어깨가 가려진 사용자가 프레임 안에 멀쩡히 있는데도
/// 자리를 옮긴다 — 6m 밖에서는 그 표시가 유일한 단서다.
public enum PoseReading: Sendable, Equatable {
    case pose(PoseFrame)
    /// 관측이 하나도 없다. 코트에 아직 아무도 없을 수 있다.
    case noPerson
    /// 사람은 잡혔지만 어깨를 믿을 수 없다. 자세를 바꿔야 한다.
    case unusable
}

/// 포즈 추정기의 경계.
///
/// 가짜를 끼울 수 있어야 `.pose` 분기와 그것을 쓰는 화면 로직이 **카메라
/// 없이** 검증된다 — `BodyPoseObservable`과 같은 수법이다. Vision 요청은
/// 시뮬레이터에서 돌지 않으므로(컴퓨트 디바이스 없음) 이 경계가 없으면
/// 포즈가 잡힌 뒤의 코드가 전부 미검증으로 남는다.
public protocol PoseEstimating: Sendable {
    func reading(
        in pixelBuffer: CVPixelBuffer,
        at timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation?
    ) async throws -> PoseReading
}

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
public struct PoseEstimator: PoseEstimating {

    /// 사람을 고를 때 어깨를 믿을지 판단하는 임계. 트리거와 같은 값을 쓴다 —
    /// 트리거가 버릴 관절로 사람을 고르면 고르자마자 신호가 끊긴다.
    public let minimumConfidence: Double

    private let request: DetectHumanBodyPoseRequest

    public init(minimumConfidence: Double = SwingTriggerProfile.default.minimumConfidence) {
        self.minimumConfidence = minimumConfidence
        self.request = DetectHumanBodyPoseRequest()
    }

    /// 프레임 하나를 읽는다.
    ///
    /// - Parameters:
    ///   - pixelBuffer: **분석용으로 줄인 사본**을 넣는다. 원본을 넣으면
    ///     1080p 추정이 프레임 예산을 넘는다([비전 파이프라인 3.7](../../../../docs/02-설계/VISION-PIPELINE.md)).
    ///
    ///     `sending`으로 받지 않는다. 받으면 호출부가 루프에서 그 버퍼를
    ///     들고 있는 것조차 "전달 후 사용"이 된다. 이 함수와 호출부는 둘 다
    ///     nonisolated이므로 격리 경계를 넘지 않고, 넘길 것도 없다.
    ///   - orientation: 버퍼가 세워진 방향. Vision이 이것을 받아 **좌표까지
    ///     맞춰 돌려준다** — 버퍼를 돌리지 않아도 된다.
    public func reading(
        in pixelBuffer: CVPixelBuffer,
        at timestamp: TimeInterval,
        orientation: CGImagePropertyOrientation? = nil
    ) async throws -> PoseReading {
        let observations = try await request.perform(on: pixelBuffer, orientation: orientation)
        return Self.reading(from: observations, at: timestamp, minimumConfidence: minimumConfidence)
    }

    /// 관측 배열을 읽을 것으로 바꾼다. Vision 없이 검증되는 자리다.
    static func reading<Observation: BodyPoseObservable>(
        from observations: [Observation],
        at timestamp: TimeInterval,
        minimumConfidence: Double
    ) -> PoseReading {
        guard !observations.isEmpty else { return .noPerson }
        guard let chosen = primary(in: observations, minimumConfidence: minimumConfidence) else {
            return .unusable
        }
        return .pose(PoseFrameAdapter.frame(from: chosen, at: timestamp))
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
