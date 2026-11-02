import CoreGraphics
import Foundation

/// Vision 정규화 좌표를 **화면에 실제로 보이는 영상 사각형** 안의 점으로 옮긴다.
///
/// ## 왜 `RenderTransform`을 쓰지 않는가
///
/// `RenderTransform`([SPEC-0040](../../../../../docs/07-기획/SPEC-0040-render-transform.md))은
/// **aspect-fill**이다. 라이브 프리뷰가 화면을 꽉 채우고 넘치는 부분을
/// 자르기 때문이다.
///
/// 리플레이는 `AVPlayerLayer`의 `videoGravity = .resizeAspect`, 즉
/// **aspect-fit**이다 — 영상 전체를 보여주고 남는 자리를 레터박스로 둔다
/// (#123). 자르면 스윙의 일부가 안 보이므로 그게 맞다.
///
/// 그래서 fill 행렬을 그대로 쓰면 오버레이가 영상보다 크게 그려지고
/// **중심에서 멀어질수록 벌어진다.** 가운데에 선 사람으로 확인하면
/// 어긋남이 작아 눈에 잘 안 띄는 종류의 오류다.
///
/// > SPEC-0121 선택지 7은 "`RenderTransform`에 pt 변환을 더한다"로 정했다.
/// > 그 근거는 "두 곳이 같은 행렬을 써야 어긋나지 않는다"였는데, **리플레이에는
/// > 그 두 곳이 없다** — 영상의 배치는 `AVPlayerLayer`가 하고 우리는 그것을
/// > 따라가기만 한다. 따라갈 대상이 `.resizeAspect`이므로 fit을 복제하는 것이
/// > 옳다. 구현에서 정정했다.
///
/// ## 왜 회전·미러링이 없는가
///
/// 사이드카를 구울 때 Vision에 `preferredTransform`에서 얻은 방향을 넘겼다.
/// 좌표가 이미 **표시 방향**으로 나와 있다(`OverlayBaker`). 후면 카메라만
/// 쓰므로 미러링도 없다.
public struct OverlayProjection: Equatable, Sendable {

    /// 뷰 안에서 영상이 실제로 차지하는 사각형.
    public let content: CGRect

    /// - Parameters:
    ///   - pixelSize: 영상의 표시 픽셀 크기. 사이드카가 들고 있다.
    ///   - viewSize: 영상을 그리는 뷰의 포인트 크기.
    public init?(pixelSize: CGSize, viewSize: CGSize) {
        guard pixelSize.width > 0, pixelSize.height > 0,
              viewSize.width > 0, viewSize.height > 0
        else { return nil }

        // `.resizeAspect`와 같은 계산. 짧은 쪽에 맞춰 넣고 가운데 둔다.
        let scale = min(
            viewSize.width / pixelSize.width,
            viewSize.height / pixelSize.height
        )
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        content = CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Vision 정규화 좌표(0~1, **좌하단** 원점) → 뷰 좌표(pt, 좌상단 원점).
    ///
    /// 0~1을 벗어나는 점도 그대로 옮긴다. 자르면 궤적이 영상 가장자리에
    /// 붙어 **거짓된 직선**이 생긴다.
    public func point(_ normalized: CGPoint) -> CGPoint {
        CGPoint(
            x: content.minX + normalized.x * content.width,
            // Vision은 y-up, 뷰는 y-down. 여기 한 곳에서만 뒤집는다.
            y: content.minY + (1 - normalized.y) * content.height
        )
    }
}
