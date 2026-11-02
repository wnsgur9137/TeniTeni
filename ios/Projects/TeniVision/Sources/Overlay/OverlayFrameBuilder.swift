import CoreGraphics
import Foundation

/// 관측 하나를 오버레이 한 프레임으로 옮긴다.
///
/// 굽는 경로에서 Vision과 `AVAssetReader`를 떼어낸 **순수 부분**이다.
/// 가짜 관측을 꽂으면 실기기 없이 전부 검증된다 — 이 작업에서 테스트가
/// 닿을 수 있는 자리를 최대한 넓히려고 나눴다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md
public enum OverlayFrameBuilder {

    /// 라켓 헤드를 그릴 최소 신뢰도.
    ///
    /// 단축이 곱해진 값과 비교하므로, 손이 카메라 쪽을 향하면 이 선 아래로
    /// 떨어지고 **그 프레임은 선을 끊는다.** 0.3은 잠정값이다 — 실기기에서
    /// 보고 조정해야 하고, 그 전까지 숫자의 근거는 없다.
    public static let racketMinimumConfidence: Double = 0.3

    /// 관측 하나 → 프레임 하나.
    ///
    /// 사람이 없으면 `nil`이다. 관절이 **하나도** 없는 프레임을 넣으면
    /// 사이드카가 "사람이 있었다"고 거짓을 말한다.
    ///
    /// - Parameters:
    ///   - side: 라켓을 든 쪽. 온보딩의 `handedness`에서 온다.
    ///   - aspect: 영상의 `픽셀 가로 / 픽셀 세로`. 추정식의 등방성 보정에
    ///     쓴다 — `RacketHeadEstimator.estimate`의 설명을 보라.
    public static func frame<Observation: RacketPoseObservable>(
        from observation: Observation,
        side: RacketSide,
        aspect: Double,
        at seconds: Double,
        minimumConfidence: Double
    ) -> OverlayFrame? {
        let pose = PoseFrameAdapter.frame(
            from: observation, at: seconds, joints: PoseJoint.allCases
        )
        guard !pose.joints.isEmpty else { return nil }

        return OverlayFrame(
            seconds: seconds,
            joints: pose.joints,
            racketHead: racketHead(
                from: observation,
                pose: pose,
                side: side,
                aspect: aspect,
                minimumConfidence: minimumConfidence
            )
        )
    }

    /// 라켓 헤드. 손이 없거나 어깨를 못 믿으면 `nil`이다.
    ///
    /// **`nil`을 실패로 보지 않는다.** 서브와 극단적 팔로스루에서는 정상적으로
    /// 비는 값이고, 그때 선을 끊는 것이 설계다.
    static func racketHead<Observation: RacketPoseObservable>(
        from observation: Observation,
        pose: PoseFrame,
        side: RacketSide,
        aspect: Double,
        minimumConfidence: Double
    ) -> RacketHead? {
        guard let hand = observation.hand(side),
              let wrist = hand.sample(for: .wrist),
              let mcp = hand.sample(for: .middleMCP)
        else { return nil }

        // 어깨는 **신뢰도 임계를 통과한 것만** 쓴다. 믿을 수 없는 어깨로
        // 만든 자는 라켓 길이를 엉뚱하게 환산한다.
        guard let left = pose.point(.leftShoulder, minimumConfidence: minimumConfidence),
              let right = pose.point(.rightShoulder, minimumConfidence: minimumConfidence)
        else { return nil }

        return RacketHeadEstimator.estimate(
            .init(
                wrist: wrist,
                middleMCP: mcp,
                leftShoulder: left,
                rightShoulder: right,
                aspect: aspect
            ),
            minimumConfidence: racketMinimumConfidence
        )
    }
}
