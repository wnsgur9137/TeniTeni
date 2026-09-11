import Foundation
import TeniVision

/// 합성 영상의 공 운동. 측면 촬영을 전제로 **카메라와 평행한 평면** 위에서만
/// 움직인다 — 깊이 방향 운동이 없으므로 m→px 환산이 프레임 내내 일정하고
/// 정답 좌표가 근사 없이 정확해진다.
///
/// `DetectTrajectoriesRequest`가 애초에 이미지 평면의 포물선만 찾으므로
/// (docs/02-설계/CAPTURE-PROTOCOL.md 5.1절) 이 단순화는 검증 목적을
/// 훼손하지 않는다.
public struct BallTrajectory: Sendable {

    /// 중력 가속도 (m/s²)
    public static let gravity = 9.81

    /// 타구 시각 (초)
    public let impactTime: Double
    /// 타구 지점 — 코트 장축 방향 위치(m), 지면 높이(m)
    public let originX: Double
    public let originY: Double
    /// 초기 속도 (m/s)
    public let velocityX: Double
    public let velocityY: Double

    /// 타구 후 경과 시간 t에서의 위치 (m)
    public func position(afterImpact t: Double) -> (x: Double, y: Double) {
        (
            x: originX + velocityX * t,
            y: originY + velocityY * t - 0.5 * Self.gravity * t * t
        )
    }

    /// 절대 시각에서의 위치. 타구 전이면 nil.
    public func position(at time: Double) -> (x: Double, y: Double)? {
        let t = time - impactTime
        guard t >= 0 else { return nil }
        let p = position(afterImpact: t)
        // 지면 아래로 내려가면 끝난 것으로 본다
        guard p.y >= 0 else { return nil }
        return p
    }

    /// 속력 (m/s) — 블러 길이 검산에 쓴다
    public func speed(at time: Double) -> Double {
        let t = max(0, time - impactTime)
        let vy = velocityY - Self.gravity * t
        return (velocityX * velocityX + vy * vy).squareRoot()
    }
}

/// 월드 좌표(m)를 이미지 좌표(px)로 옮기는 측면 카메라.
public struct SideOnCamera: Sendable {
    public let widthPx: Int
    public let heightPx: Int
    /// 카메라–피사체 평면 거리 (m)
    public let distanceMeters: Double
    /// 렌즈 높이 (m)
    public let heightMeters: Double
    /// 수평 시야각 (도)
    public let fieldOfView: Double

    /// 1 m가 몇 px인가. 공 크기 계산과 같은 기하를 쓴다.
    public var pixelsPerMeter: Double {
        let frameWidth = 2 * distanceMeters * tan(fieldOfView * .pi / 180 / 2)
        guard frameWidth > 0 else { return 0 }
        return Double(widthPx) / frameWidth
    }

    /// 공 지름 (px). **BallGeometry가 단일 출처**다 — 여기서 다시 계산하지 않는다.
    public var ballDiameterPx: Double {
        BallGeometry.pixelDiameter(
            width: Int32(widthPx),
            fieldOfView: Float(fieldOfView),
            distanceMeters: distanceMeters
        )
    }

    /// 화면 중앙이 바라보는 월드 x 좌표 (m)
    public let centerX: Double

    /// 월드 → 이미지. y는 위가 양수인 월드에서 아래가 양수인 이미지로 뒤집힌다.
    public func project(x: Double, y: Double) -> (px: Double, py: Double) {
        let scale = pixelsPerMeter
        return (
            px: Double(widthPx) / 2 + (x - centerX) * scale,
            py: Double(heightPx) / 2 - (y - heightMeters) * scale
        )
    }
}
