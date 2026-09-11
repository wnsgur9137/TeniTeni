import Foundation
import TeniVision

/// `Synth` 인자를 렌더링 가능한 형태로 확정한다.
/// 커맨드와 분리한 이유는 테스트에서 영상 파일 없이 계산만 검증하기 위함이다.
public struct SynthPlan {

    public let camera: SideOnCamera
    public let trajectories: [BallTrajectory]
    public let fps: Double
    public let exposureSeconds: Double
    public let exposureLabel: String
    public let frameCount: Int
    public let blurSampleCount: Int
    public let renderer: FrameRenderer
    public let seed: UInt64
    public let noiseSigma: Double
    public let clipId: String

    /// 타구 직후 속력으로 계산한 블러 길이 (px). 프로토콜 5.3 표와 대조하는 값.
    public let referenceBlurLengthPx: Double

    public init(command: Synth) throws {
        fps = command.fps
        exposureSeconds = command.exposure.seconds
        exposureLabel = command.exposure.label
        seed = command.seed
        noiseSigma = command.noise

        let movieURL = URL(fileURLWithPath: command.out)
        clipId = command.clipId ?? movieURL.deletingPathExtension().lastPathComponent

        // 화면 중앙을 첫 타구 지점보다 약간 앞에 둬서 공이 프레임을 가로지르게 한다
        let originX = 0.0
        let speed = command.ballSpeed / 3.6
        let angle = command.launchAngle * .pi / 180

        camera = SideOnCamera(
            widthPx: command.width,
            heightPx: command.height,
            distanceMeters: command.distance,
            heightMeters: command.cameraHeight,
            fieldOfView: command.fov,
            centerX: originX + 0.35 * (2 * command.distance * tan(command.fov * .pi / 180 / 2))
        )

        trajectories = (0..<command.hits).map { index in
            BallTrajectory(
                impactTime: 0.3 + Double(index) * command.hitInterval,
                originX: originX,
                originY: command.contactHeight,
                velocityX: speed * cos(angle),
                velocityY: speed * sin(angle)
            )
        }

        let duration = 0.3 + Double(command.hits - 1) * command.hitInterval + command.hitInterval
        frameCount = max(1, Int((duration * fps).rounded()))

        referenceBlurLengthPx = speed * camera.pixelsPerMeter * exposureSeconds

        // 하위 프레임 간 공 이동이 1px 이하가 되어야 계단이 보이지 않는다.
        // 정확한 필요 표본 수를 못 박은 문헌이 없어 이 규칙을 쓴다
        // (docs/08-레퍼런스/ml/MotionBlur.md 2절).
        blurSampleCount = command.blurSamples
            ?? max(8, Int(referenceBlurLengthPx.rounded(.up)))

        renderer = FrameRenderer(
            width: command.width,
            height: command.height,
            backgroundLevel: command.background,
            ballLevel: command.ballBrightness,
            noiseSigma: command.noise
        )
    }

    public struct Output {
        public let frames: [[UInt8]]
        public let groundTruth: GroundTruth
        public let referenceBlurLengthPx: Double
    }

    /// 프레임 i의 노출 구간은 [i/fps, i/fps + exposure]다.
    /// 하위 표본은 그 구간을 균일 분할한 시각에 놓는다 — 오프라인 생성이라
    /// 확률적 표본화로 노이즈를 들일 이유가 없다.
    public func sampleTimes(frame: Int) -> [Double] {
        let start = Double(frame) / fps
        guard blurSampleCount > 1 else { return [start + exposureSeconds / 2] }
        let step = exposureSeconds / Double(blurSampleCount)
        return (0..<blurSampleCount).map { start + (Double($0) + 0.5) * step }
    }

    public func render() -> Output {
        var noise = NoiseGenerator(seed: seed)
        var frames: [[UInt8]] = []
        var centers: [GroundTruth.BallCenter] = []
        let radius = camera.ballDiameterPx / 2

        for frame in 0..<frameCount {
            let times = sampleTimes(frame: frame)
            var allPositions: [(px: Double, py: Double)] = []

            // 궤적마다 따로 모은다. 합쳐버리면 어느 타구의 공인지 잃고,
            // 정답에 한 공만 남는다.
            for (hitIndex, trajectory) in trajectories.enumerated() {
                let projected = times.compactMap { time -> (px: Double, py: Double)? in
                    guard let world = trajectory.position(at: time) else { return nil }
                    return camera.project(x: world.x, y: world.y)
                }
                guard !projected.isEmpty else { continue }

                allPositions.append(contentsOf: projected)

                let midTime = Double(frame) / fps + exposureSeconds / 2
                let first = projected.first!
                let last = projected.last!
                let blur = ((last.px - first.px) * (last.px - first.px)
                    + (last.py - first.py) * (last.py - first.py)).squareRoot()
                centers.append(
                    .init(
                        frame: frame,
                        hitIndex: hitIndex,
                        x: projected.reduce(0) { $0 + $1.px } / Double(projected.count),
                        y: projected.reduce(0) { $0 + $1.py } / Double(projected.count),
                        blurLengthPx: blur,
                        speedMetersPerSecond: trajectory.speed(at: midTime)
                    )
                )
            }

            // 화면 밖으로 완전히 나간 표본은 피복률이 0이므로 그대로 두면 된다
            frames.append(
                renderer.render(
                    ballCenters: allPositions,
                    sampleCount: blurSampleCount,
                    ballRadiusPx: radius,
                    noise: &noise
                )
            )
        }

        let impactFrames = trajectories.map { Int(($0.impactTime * fps).rounded()) }

        let truth = GroundTruth(
            clipId: clipId,
            condition: .init(location: "synthetic", light: "uniform", background: "simple"),
            capture: .init(
                fps: fps,
                resolution: "\(camera.widthPx)x\(camera.heightPx)",
                exposureDuration: exposureLabel,
                distanceM: camera.distanceMeters,
                heightM: camera.heightMeters,
                videoFieldOfView: camera.fieldOfView
            ),
            groundTruth: .init(impactFrames: impactFrames, ballCenters: centers),
            synthetic: .init(
                generator: "teni synth",
                ballDiameterPx: camera.ballDiameterPx,
                pixelsPerMeter: camera.pixelsPerMeter,
                blurSamplesPerFrame: blurSampleCount,
                noiseSigma: noiseSigma,
                seed: seed,
                rollingShutter: false
            )
        )

        return Output(
            frames: frames,
            groundTruth: truth,
            referenceBlurLengthPx: referenceBlurLengthPx
        )
    }
}
