import CoreGraphics
import Foundation
import Testing
import simd
@testable import TeniVision

/// 부동소수 비교 허용오차. `==`를 쓰면 간헐적으로 깨진다.
private let tolerance: Float = 1e-4

private func ~= (lhs: Float, rhs: Float) -> Bool { abs(lhs - rhs) < tolerance }

private func expectNDC(
    _ actual: SIMD2<Float>, _ x: Float, _ y: Float,
    _ label: String, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        actual.x ~= x && actual.y ~= y,
        "\(label) — 기대 (\(x), \(y)) 실제 (\(actual.x), \(actual.y))",
        sourceLocation: sourceLocation
    )
}

/// 네 모서리와 중심의 NDC를 한 번에 얻는다.
private func corners(_ t: RenderTransform) -> [SIMD2<Float>] {
    [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        .map { t.ndc(imagePoint: $0) }
}

@Suite("RenderTransform")
struct RenderTransformTests {

    // MARK: - 스케일

    @Test("종횡비가 같으면 스케일이 1이다")
    func 동일_종횡비() {
        let t = RenderTransform(
            bufferSize: .init(width: 1920, height: 1080),
            viewSize: .init(width: 1920, height: 1080),
            rotationAngle: 0, isMirrored: false
        )
        #expect(t.scale.x ~= 1)
        #expect(t.scale.y ~= 1)
    }

    @Test("버퍼가 뷰보다 넓으면 x가 넘치고, 좁으면 y가 넘친다")
    func aspect_fill_방향() {
        let wide = RenderTransform(
            bufferSize: .init(width: 1920, height: 1080),   // 1.778
            viewSize: .init(width: 1000, height: 1000),     // 1.0
            rotationAngle: 0, isMirrored: false
        )
        #expect(wide.scale.x ~= 1920.0 / 1080.0, "넘치는 축은 x")
        #expect(wide.scale.y ~= 1, "짧은 축은 그대로")

        // 정사각 버퍼를 세로 뷰에 채우려면 높이를 맞추고 **가로를 잘라낸다.**
        // 직관과 반대로 보이지만, 덮으려면 짧은 축을 기준으로 키워야 한다.
        let square = RenderTransform(
            bufferSize: .init(width: 1000, height: 1000),   // 1.0
            viewSize: .init(width: 1080, height: 1920),     // 0.5625
            rotationAngle: 0, isMirrored: false
        )
        #expect(square.scale.x ~= 1000.0 / 1000.0 / (1080.0 / 1920.0), "가로가 잘린다")
        #expect(square.scale.y ~= 1)

        // y가 넘치려면 버퍼가 뷰보다 **좁아야** 한다.
        let narrow = RenderTransform(
            bufferSize: .init(width: 1000, height: 1000),   // 1.0
            viewSize: .init(width: 1920, height: 1080),     // 1.778
            rotationAngle: 0, isMirrored: false
        )
        #expect(narrow.scale.x ~= 1)
        #expect(narrow.scale.y ~= 1920.0 / 1080.0, "넘치는 축은 y")
    }

    /// SPEC-0040 구현 선택지 2. 설계 4.3의 예시 코드가 틀렸던 지점이다.
    @Test("90° 회전에서 스케일이 회전 후 종횡비로 계산된다")
    func 회전_후_종횡비() {
        let t = RenderTransform(
            bufferSize: .init(width: 1920, height: 1080),   // 센서는 가로
            viewSize: .init(width: 390, height: 844),       // 뷰는 세로
            rotationAngle: 90, isMirrored: false
        )
        // 회전 후 버퍼 1080×1920 → 0.5625, 뷰 0.46209 → 1.2173
        // 회전 전으로 계산하면 3.8473이 나온다 (3.16배 과확대)
        let expected = Float((1080.0 / 1920.0) / (390.0 / 844.0))
        #expect(t.scale.x ~= expected, "기대 \(expected), 실제 \(t.scale.x)")
        #expect(t.scale.x < 2, "3.847이 나오면 회전 전 종횡비로 계산한 것이다")
    }

    /// 회전이 들어가면 넘침 배율이 달라져야 한다. 설계 4.3은 회전 전 종횡비로
    /// 계산해 90°에서 2.436이 아니라 7.695를 냈다 — 3.16배 과확대다.
    @Test("각도마다 정확히 필요한 만큼만 넘친다")
    func 과확대_없음() {
        let landscape = Float(1920.0 / 1080.0)          // 센서 그대로
        let portrait = Float(1080.0 / 1920.0)           // 회전 후
        let view = Float(390.0 / 844.0)

        let expected: [CGFloat: Float] = [
            0: 2 * landscape / view,      // 7.695 — 회전 없이 세로 뷰를 채우려면 이만큼 필요
            180: 2 * landscape / view,
            90: 2 * portrait / view,      // 2.435
            270: 2 * portrait / view,
        ]

        for (angle, expectedLoose) in expected {
            let t = RenderTransform(
                bufferSize: .init(width: 1920, height: 1080),
                viewSize: .init(width: 390, height: 844),
                rotationAngle: angle, isMirrored: false
            )
            let pts = corners(t)
            let spanX = pts.map(\.x).max()! - pts.map(\.x).min()!
            let spanY = pts.map(\.y).max()! - pts.map(\.y).min()!

            // 한 축은 정확히 [-1,1]을 덮고, 다른 축만 넘친다.
            #expect(min(spanX, spanY) ~= 2, "\(angle)° — 짧은 축이 뷰를 정확히 덮어야 한다")
            #expect(
                max(spanX, spanY) ~= expectedLoose,
                "\(angle)° — 기대 \(expectedLoose), 실제 \(max(spanX, spanY))"
            )
        }
    }

    /// 위 테스트가 실제로 회전을 구분하는지 못박는다. 회전 전 종횡비로
    /// 계산하면 90°도 0°와 같은 7.695가 나와 구분이 사라진다.
    @Test("90°는 0°보다 3.16배 덜 확대된다")
    func 회전이_배율을_바꾼다() {
        func loose(_ angle: CGFloat) -> Float {
            let pts = corners(RenderTransform(
                bufferSize: .init(width: 1920, height: 1080),
                viewSize: .init(width: 390, height: 844),
                rotationAngle: angle, isMirrored: false
            ))
            let spanX = pts.map(\.x).max()! - pts.map(\.x).min()!
            let spanY = pts.map(\.y).max()! - pts.map(\.y).min()!
            return max(spanX, spanY)
        }
        let ratio = loose(0) / loose(90)
        #expect(ratio ~= Float(1920.0 / 1080.0) / Float(1080.0 / 1920.0), "기대 3.160, 실제 \(ratio)")
    }

    // MARK: - 좌표

    @Test("스케일이 1이면 모서리가 NDC 모서리로 간다")
    func 모서리_왕복() {
        let t = RenderTransform(
            bufferSize: .init(width: 1000, height: 1000),
            viewSize: .init(width: 1000, height: 1000),
            rotationAngle: 0, isMirrored: false
        )
        expectNDC(t.ndc(imagePoint: .init(x: 0, y: 0)), -1, 1, "이미지 좌상 → NDC 좌상")
        expectNDC(t.ndc(imagePoint: .init(x: 1, y: 1)), 1, -1, "이미지 우하 → NDC 우하")
        expectNDC(t.ndc(imagePoint: .init(x: 1, y: 0)), 1, 1, "이미지 우상")
        expectNDC(t.ndc(imagePoint: .init(x: 0, y: 1)), -1, -1, "이미지 좌하")
    }

    @Test("중심은 모든 조합에서 원점이다")
    func 중심_불변() {
        for angle in [CGFloat(0), 90, 180, 270] {
            for mirrored in [false, true] {
                let t = RenderTransform(
                    bufferSize: .init(width: 1920, height: 1080),
                    viewSize: .init(width: 390, height: 844),
                    rotationAngle: angle, isMirrored: mirrored
                )
                expectNDC(
                    t.ndc(imagePoint: .init(x: 0.5, y: 0.5)), 0, 0,
                    "\(angle)° mirrored=\(mirrored)"
                )
            }
        }
    }

    @Test("Vision 좌표는 y가 뒤집힌다")
    func vision_y_뒤집기() {
        let t = RenderTransform(
            bufferSize: .init(width: 1000, height: 1000),
            viewSize: .init(width: 1000, height: 1000),
            rotationAngle: 0, isMirrored: false
        )
        // Vision은 좌하단 원점이므로 y=0이 화면 아래다.
        expectNDC(t.ndc(visionPoint: .init(x: 0, y: 0)), -1, -1, "Vision 좌하 → NDC 아래")
        expectNDC(t.ndc(visionPoint: .init(x: 0, y: 1)), -1, 1, "Vision 좌상 → NDC 위")

        let mid = t.ndc(visionPoint: .init(x: 0.5, y: 0.5))
        expectNDC(mid, 0, 0, "Vision 중심")
    }

    // MARK: - 미러링

    @Test("전면 카메라는 x만 뒤집는다")
    func 미러링() {
        func make(_ mirrored: Bool) -> RenderTransform {
            RenderTransform(
                bufferSize: .init(width: 1920, height: 1080),
                viewSize: .init(width: 390, height: 844),
                rotationAngle: 90, isMirrored: mirrored
            )
        }
        let back = make(false), front = make(true)
        for point in [CGPoint(x: 0.2, y: 0.3), .init(x: 0.9, y: 0.1), .init(x: 0, y: 1)] {
            let b = back.ndc(imagePoint: point)
            let f = front.ndc(imagePoint: point)
            #expect(f.x ~= -b.x, "x 부호가 뒤집혀야 한다 — \(point)")
            #expect(f.y ~= b.y, "y는 그대로여야 한다 — \(point)")
        }
    }

    // MARK: - 대칭성 교차 검증

    /// 손으로 계산한 기댓값 자체가 틀릴 수 있으므로 대칭성으로 교차 검증한다.
    @Test("90°를 네 번 돌리면 제자리다")
    func 사분회전_항등() {
        let size = CGSize(width: 1000, height: 1000)
        let base = RenderTransform(
            bufferSize: size, viewSize: size, rotationAngle: 0, isMirrored: false
        )
        let full = RenderTransform(
            bufferSize: size, viewSize: size, rotationAngle: 360, isMirrored: false
        )
        for point in [CGPoint(x: 0.1, y: 0.2), .init(x: 0.7, y: 0.9)] {
            let b = base.ndc(imagePoint: point)
            let f = full.ndc(imagePoint: point)
            #expect(f.x ~= b.x && f.y ~= b.y, "360° = 0° — \(point)")
        }
    }

    @Test("180°는 두 축 모두 뒤집는다")
    func 반회전() {
        let size = CGSize(width: 1000, height: 1000)
        let base = RenderTransform(
            bufferSize: size, viewSize: size, rotationAngle: 0, isMirrored: false
        )
        let half = RenderTransform(
            bufferSize: size, viewSize: size, rotationAngle: 180, isMirrored: false
        )
        for point in [CGPoint(x: 0.1, y: 0.2), .init(x: 0.7, y: 0.9)] {
            let b = base.ndc(imagePoint: point)
            let h = half.ndc(imagePoint: point)
            #expect(h.x ~= -b.x && h.y ~= -b.y, "180°는 부호 반전 — \(point)")
        }
    }

    // MARK: - 경계

    @Test("0 크기를 넘겨도 죽지 않는다")
    func 영_크기() {
        let t = RenderTransform(
            bufferSize: .zero, viewSize: .init(width: 100, height: 100),
            rotationAngle: 0, isMirrored: false
        )
        #expect(t.scale.x ~= 1, "나눗셈이 일어나면 안 된다")
        #expect(t.scale.y ~= 1)
        let p = t.ndc(imagePoint: .init(x: 0.5, y: 0.5))
        #expect(p.x.isFinite && p.y.isFinite, "NaN이 나오면 렌더가 통째로 사라진다")
    }

    @Test("음수·초과 각도를 정규화한다")
    func 각도_정규화() {
        #expect(RenderTransform.isQuarterTurn(90))
        #expect(RenderTransform.isQuarterTurn(270))
        #expect(RenderTransform.isQuarterTurn(-90), "음수 각도")
        #expect(RenderTransform.isQuarterTurn(450), "360 초과")
        #expect(!RenderTransform.isQuarterTurn(0))
        #expect(!RenderTransform.isQuarterTurn(180))
        #expect(!RenderTransform.isQuarterTurn(360))
    }
}
