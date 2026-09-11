import Foundation

/// 테니스공의 화면상 크기 계산. **이 식은 여기에만 존재한다.**
///
/// CAPTURE-PROTOCOL 5.1절의 거리별 표가 이 식에 기반한다. 표와 코드가
/// 어긋나면 objectMinimumNormalizedRadius 파라미터가 통째로 틀어지므로
/// 중복 구현을 두지 않는다.
public enum BallGeometry {

    /// 국제테니스연맹 규격 지름 (m)
    public static let ballDiameterMeters = 0.067

    /// 주어진 화각·거리에서 공이 몇 픽셀로 보이는가
    /// - Parameters:
    ///   - width: 가로 해상도 (px)
    ///   - fieldOfView: 수평 시야각 (도)
    ///   - distanceMeters: 카메라–피사체 거리 (m)
    public static func pixelDiameter(
        width: Int32,
        fieldOfView: Float,
        distanceMeters: Double
    ) -> Double {
        guard fieldOfView > 0, distanceMeters > 0, width > 0 else { return 0 }
        let halfFOV = Double(fieldOfView) * .pi / 180 / 2
        let frameWidthMeters = 2 * distanceMeters * tan(halfFOV)
        guard frameWidthMeters > 0 else { return 0 }
        return Double(width) * ballDiameterMeters / frameWidthMeters
    }
}
