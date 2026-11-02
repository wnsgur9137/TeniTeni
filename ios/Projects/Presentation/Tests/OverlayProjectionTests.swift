import CoreGraphics
import Foundation
import Testing
@testable import Presentation

/// `AVPlayerLayer`의 `videoGravity = .resizeAspect`를 복제한 계산이다.
/// 틀리면 오버레이가 영상보다 크거나 작게 그려지고, **중심에서 멀어질수록
/// 벌어진다** — 가운데에 선 사람으로 확인하면 눈에 잘 안 띄는 종류다.
@Suite("오버레이 투영")
struct OverlayProjectionTests {

    // MARK: - 레터박스

    @Test("뷰가 영상보다 넓으면 좌우에 레터박스가 생긴다")
    func 좌우_레터박스() throws {
        // 16:9 영상을 2:1 뷰에 넣는다 → 높이에 맞고 좌우가 남는다
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 800, height: 400)
            )
        )
        #expect(abs(projection.content.height - 400) < 1e-9)
        #expect(abs(projection.content.width - 400 * 16 / 9) < 1e-9)
        #expect(abs(projection.content.minY) < 1e-9)
        // 가운데 정렬
        #expect(abs(projection.content.midX - 400) < 1e-9)
    }

    @Test("뷰가 영상보다 좁으면 위아래에 레터박스가 생긴다")
    func 위아래_레터박스() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 390, height: 844)
            )
        )
        #expect(abs(projection.content.width - 390) < 1e-9)
        #expect(abs(projection.content.height - 390 * 9 / 16) < 1e-9)
        #expect(abs(projection.content.midY - 422) < 1e-9)
    }

    /// ⚠️ 높이를 `844 * 9 / 16`으로 쓰면 **정수 나눗셈**이 된다 —
    /// `CGSize`에 `init(width: Int, height: Int)` 오버로드가 있어서 리터럴이
    /// `Int`로 묶이고 474.75가 474가 된다. 값을 그대로 적는다.
    @Test("종횡비가 같으면 뷰를 꽉 채운다")
    func 딱_맞음() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 844, height: 474.75)
            )
        )
        #expect(abs(projection.content.minX) < 1e-9)
        #expect(abs(projection.content.minY) < 1e-9)
        #expect(abs(projection.content.width - 844) < 1e-9)
    }

    // MARK: - 좌표

    /// Vision은 좌하단 원점(y-up), 뷰는 좌상단 원점(y-down)이다.
    /// **여기 한 곳에서만 뒤집는다.**
    @Test("y를 뒤집는다 — 아래가 0이던 것이 아래가 높이가 된다")
    func y_뒤집기() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 100, height: 100),
                viewSize: CGSize(width: 200, height: 200)
            )
        )
        // 정사각 100을 200 뷰에 → 꽉 찬다
        let bottom = projection.point(CGPoint(x: 0, y: 0))
        let top = projection.point(CGPoint(x: 0, y: 1))
        #expect(abs(bottom.y - 200) < 1e-9)
        #expect(abs(top.y) < 1e-9)
    }

    @Test("중심은 중심으로 간다")
    func 중심() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 844, height: 390)
            )
        )
        let center = projection.point(CGPoint(x: 0.5, y: 0.5))
        #expect(abs(center.x - 422) < 1e-9)
        #expect(abs(center.y - 195) < 1e-9)
    }

    @Test("레터박스가 있으면 좌표가 그만큼 밀린다")
    func 밀림() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 1920, height: 1080),
                viewSize: CGSize(width: 800, height: 400)
            )
        )
        // 영상 왼쪽 끝(x=0)은 뷰의 0이 아니라 레터박스 뒤다.
        let left = projection.point(CGPoint(x: 0, y: 0.5))
        #expect(left.x > 0)
        #expect(abs(left.x - projection.content.minX) < 1e-9)
    }

    /// 자르면 궤적이 영상 가장자리에 붙어 **거짓된 직선**이 생긴다.
    @Test("0~1을 벗어나는 점도 그대로 옮긴다")
    func 범위_밖() throws {
        let projection = try #require(
            OverlayProjection(
                pixelSize: CGSize(width: 100, height: 100),
                viewSize: CGSize(width: 100, height: 100)
            )
        )
        let outside = projection.point(CGPoint(x: 1.5, y: -0.5))
        #expect(outside.x > 100)
        #expect(outside.y > 100)
    }

    // MARK: - 못 만드는 입력

    @Test("크기가 0이면 만들지 않는다")
    func 크기_0() {
        #expect(OverlayProjection(pixelSize: .zero, viewSize: CGSize(width: 10, height: 10)) == nil)
        #expect(OverlayProjection(pixelSize: CGSize(width: 10, height: 10), viewSize: .zero) == nil)
        #expect(
            OverlayProjection(
                pixelSize: CGSize(width: 10, height: 0), viewSize: CGSize(width: 10, height: 10)
            ) == nil
        )
    }
}
