import DesignSystem
import Domain
import SwiftUI
import TeniVision

/// 영상 위에 스켈레톤 또는 라켓 궤적을 그린다.
///
/// `Canvas` 하나다. Metal이 아닌 이유는 [ADR-0006](../../../../../docs/05-결정/adr/ADR-0006-replay-overlay-layers.md)에
/// 있다 — 리플레이는 슬로우 모션이 기본이라 초당 15~30프레임만 그리면 되고,
/// Metal이 해결하는 문제(실시간 지연)가 하나도 남지 않은 자리다.
struct ReplayOverlayCanvas: View {

    let layer: OverlayLayer
    /// 지금 프레임. `nil`이면 그 시각에 데이터가 없다 — **아무것도 그리지
    /// 않는다.** 직전 프레임을 다시 그리면 영상이 멈춘 것처럼 보인다.
    let frame: OverlayFrame?
    /// 라켓 궤적용 과거 구간. 시간 순서다.
    let trail: [RacketHead?]
    let pixelSize: CGSize
    let side: RacketSide

    /// 관절·본을 그릴 최소 신뢰도. 이보다 낮으면 선을 긋지 않는다.
    ///
    /// 알파로만 표현하면 0.02인 관절도 희미하게 보이고, **희미한 선이 몸
    /// 밖으로 뻗으면** 사용자는 그것을 "앱이 잘못 봤다"가 아니라 "내 자세가
    /// 이상하다"로 읽는다.
    private static let minimumConfidence: Double = 0.15

    var body: some View {
        Canvas { context, size in
            guard layer.needsSidecar,
                  let projection = OverlayProjection(pixelSize: pixelSize, viewSize: size)
            else { return }

            switch layer {
            case .off:
                break
            case .skeleton:
                drawSkeleton(in: &context, projection: projection)
            case .racket:
                drawRacket(in: &context, projection: projection)
            }
        }
        // 영상 위에 겹치기만 한다. 탭은 아래(전체화면 토글)로 보낸다.
        .allowsHitTesting(false)
    }

    // MARK: - 스켈레톤

    private func drawSkeleton(in context: inout GraphicsContext, projection: OverlayProjection) {
        guard let frame else { return }
        let racketBones = Set(SkeletonBone.racketArm(side).map(Key.init))

        for bone in SkeletonBone.all {
            guard let a = frame.joints[bone.0], let b = frame.joints[bone.1] else { continue }
            // 본의 신뢰도는 **두 끝 중 낮은 쪽**이다. 한쪽이 안 믿기면 그
            // 선의 위치도 믿을 수 없다.
            let confidence = min(a.confidence, b.confidence)
            guard confidence >= Self.minimumConfidence else { continue }

            var path = Path()
            path.move(to: projection.point(a.point))
            path.addLine(to: projection.point(b.point))

            let isRacketArm = racketBones.contains(Key(bone))
            context.stroke(
                path,
                with: .color(
                    (isRacketArm ? Token.Overlay.racketArm : Token.Overlay.bone)
                        .opacity(confidence)
                ),
                style: StrokeStyle(lineWidth: isRacketArm ? 3 : 2.5, lineCap: .round)
            )
        }

        for (joint, sample) in frame.joints {
            guard sample.confidence >= Self.minimumConfidence else { continue }
            // 얼굴 관절은 점만 찍는다. 본을 잇지 않는 것과 같은 이유다.
            let radius: CGFloat = Self.isFace(joint) ? 2 : 3
            let center = projection.point(sample.point)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(Token.Overlay.joint.opacity(sample.confidence))
            )
        }
    }

    private static func isFace(_ joint: PoseJoint) -> Bool {
        switch joint {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar: true
        default: false
        }
    }

    // MARK: - 라켓 궤적

    private func drawRacket(in context: inout GraphicsContext, projection: OverlayProjection) {
        // 과거로 갈수록 흐리게. 선분마다 알파가 달라야 하므로 한 Path로
        // 묶지 않고 **구간마다 그린다.**
        let count = trail.count
        guard count > 1 else { return }

        for index in 1..<count {
            // `nil`은 **끊는다.** 이어 그리면 틀린 위치를 확신 있게
            // 보여주는 것이 되고, 그것이 추정을 숨기는 것보다 나쁘다.
            guard let from = trail[index - 1], let to = trail[index] else { continue }

            let age = Double(index) / Double(count - 1)
            // 신뢰도와 나이를 함께 쓴다. 둘 중 하나만 쓰면 "오래된 확실한
            // 점"과 "방금의 못 믿을 점"이 같은 농도로 보인다.
            let alpha = min(from.confidence, to.confidence) * (0.18 + 0.82 * age)

            var path = Path()
            path.move(to: projection.point(from.point))
            path.addLine(to: projection.point(to.point))
            context.stroke(
                path,
                with: .color(Token.Overlay.racketTrail.opacity(alpha)),
                style: StrokeStyle(lineWidth: 1.6 + 1.6 * age, lineCap: .round)
            )
        }

        // 지금 프레임의 헤드. 채운 원으로 "여기"를 말한다.
        guard let head = frame?.racketHead else { return }
        let center = projection.point(head.point)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
            with: .color(Token.Overlay.racketTrail)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - 9.5, y: center.y - 9.5, width: 19, height: 19)),
            with: .color(Token.Overlay.racketTrail.opacity(0.42)),
            lineWidth: 1.6
        )
    }

    /// 본 쌍을 `Set`에 넣기 위한 키. 튜플은 `Hashable`이 아니다.
    private struct Key: Hashable {
        let a: PoseJoint
        let b: PoseJoint

        init(_ bone: (PoseJoint, PoseJoint)) {
            self.a = bone.0
            self.b = bone.1
        }
    }
}
