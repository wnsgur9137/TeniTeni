import Foundation
import simd

/// 카메라 텍스처와 관절 좌표에 **같은 변환**을 적용하는 행렬.
///
/// Vision은 정규화 좌표 + 좌하단 원점, Metal NDC는 -1~1 + 좌하단 원점이다.
/// 여기에 aspect-fill 크롭, 디바이스 회전, 전면 카메라 미러링이 겹친다.
///
/// `AVCaptureVideoPreviewLayer`를 쓰지 않으므로
/// (`layerPointConverted(fromCaptureDevicePoint:)`도 쓸 수 없다) 변환을 직접
/// 만들되, **두 곳이 같은 행렬을 쓰게 해서 어긋날 수 없게** 한다.
///
/// 근거: docs/02-설계/SKELETON-OVERLAY.md 4.3 · docs/07-기획/SPEC-0040
public struct RenderTransform: Sendable, Equatable {

    /// 정규화 이미지 좌표(0~1, **좌상단** 원점) → NDC(-1~1, 좌하단 원점)
    public let matrix: simd_float4x4

    /// aspect-fill로 넘치는 배율. **화면 축 기준**이다 — 이미지 축이 아니다.
    ///
    /// 회전이 들어가면 둘이 갈린다. `sx`·`sy`는 회전 후 버퍼(= 화면 방향)로
    /// 계산되고, `(px, py)` 스왑이 이미지 축으로 되돌린 뒤 회전이 다시
    /// 화면 축으로 돌려놓는다. 그래서 `scale.x`는 언제나 화면 가로의 초과분이다.
    ///
    ///     0°   scale = (3.847, 1.0)   화면 x가 3.847배 넘침
    ///     90°  scale = (1.217, 1.0)   화면 x가 1.217배 넘침
    ///
    /// 디버깅과 테스트를 위해 드러낸다.
    public let scale: SIMD2<Float>

    /// - Parameters:
    ///   - bufferSize: **센서가 준 그대로**의 픽셀 크기. 회전을 미리 적용하지 마라 —
    ///     이 타입이 `rotationAngle`을 보고 처리한다.
    ///   - viewSize: 그릴 뷰의 포인트 크기.
    ///   - rotationAngle: `AVCaptureDevice.RotationCoordinator.videoRotationAngle`이
    ///     내는 **도(degree)**. 호출부가 라디안으로 바꾸면 그 변환이 두 곳에 생긴다.
    ///
    ///     **90의 배수만 지원한다.** `videoRotationAngle`이 0·90·180·270만
    ///     내므로 지금은 그것으로 충분하다. 임의 각도를 넣으면 뷰는 덮지만
    ///     확대율이 틀리고, 45°·135°·225°·315° 경계에서 배율이 불연속으로
    ///     튄다(6.855 → 3.141). 임의 각도를 제대로 다루려면 **회전된 사각형의
    ///     바운딩 박스**로 aspect-fill을 계산해야 하는데, 이 구현은 그것을
    ///     하지 않는다. 필요해지면 그때 넓힌다.
    ///   - isMirrored: 전면 카메라면 `true`.
    public init(
        bufferSize: CGSize,
        viewSize: CGSize,
        rotationAngle: CGFloat,
        isMirrored: Bool
    ) {
        // ★ aspect-fill은 **회전 후** 버퍼 크기로 계산해야 한다.
        //
        // 회전을 나중에 곱하면 비균등 스케일이 축과 함께 돌아간다. 회전 전
        // 종횡비로 구한 값을 그대로 쓰면 배율이 어긋난다 — 센서 1920×1080,
        // 뷰 390×844, 90°에서 1.217배가 나와야 하는데 3.847배가 나온다.
        //
        // 관절에도 같은 행렬이 곱해지므로 스켈레톤은 영상과 어긋나지 않는다.
        // 둘 다 똑같이 과확대될 뿐이라 "스켈레톤이 안 맞는다"로는 드러나지
        // 않고 화면이 3배 확대돼 보인다. 눈으로 잡기 어려워 테스트로 고정한다.
        let rotated = Self.isQuarterTurn(rotationAngle)
        let effective = rotated
            ? CGSize(width: bufferSize.height, height: bufferSize.width)
            : bufferSize

        var sx: Float = 1
        var sy: Float = 1
        if effective.height > 0, viewSize.height > 0, effective.width > 0, viewSize.width > 0 {
            let bufferAspect = Float(effective.width / effective.height)
            let viewAspect = Float(viewSize.width / viewSize.height)
            if bufferAspect > viewAspect {
                sx = bufferAspect / viewAspect
            } else {
                sy = viewAspect / bufferAspect
            }
        }

        // 회전으로 축이 바뀌므로 스케일도 함께 바꿔 곱한다.
        // 회전 전 x축에 곱한 값이 회전 후 화면의 y축이 된다.
        let (px, py) = rotated ? (sy, sx) : (sx, sy)

        // 0~1 → -1~1, y축 뒤집기 (이미지는 y-down, NDC는 y-up)
        var m = simd_float4x4(diagonal: .init(2 * px, -2 * py, 1, 1))
        m.columns.3 = .init(-px, py, 0, 1)

        m = Self.rotationZ(degrees: Float(rotationAngle)) * m

        if isMirrored {
            m = simd_float4x4(diagonal: .init(-1, 1, 1, 1)) * m
        }

        self.matrix = m
        self.scale = .init(sx, sy)
    }

    /// Vision 정규화 좌표(**좌하단** 원점, y-up) → NDC
    public func ndc(visionPoint point: CGPoint) -> SIMD2<Float> {
        // Vision은 y-up이므로 이미지 좌표계(y-down)로 뒤집어서 넣는다.
        ndc(imagePoint: CGPoint(x: point.x, y: 1 - point.y))
    }

    /// 정규화 이미지 좌표(**좌상단** 원점, y-down) → NDC
    public func ndc(imagePoint point: CGPoint) -> SIMD2<Float> {
        let v = matrix * SIMD4<Float>(Float(point.x), Float(point.y), 0, 1)
        return .init(v.x, v.y)
    }

    /// 90°·270° 계열인지. 360을 넘거나 음수인 각도도 받는다.
    static func isQuarterTurn(_ degrees: CGFloat) -> Bool {
        let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        return abs(normalized - 90) < 45 || abs(normalized - 270) < 45
    }

    static func rotationZ(degrees: Float) -> simd_float4x4 {
        let r = degrees * .pi / 180
        let c = cos(r), s = sin(r)
        return simd_float4x4(
            .init(c, s, 0, 0),
            .init(-s, c, 0, 0),
            .init(0, 0, 1, 0),
            .init(0, 0, 0, 1)
        )
    }
}
