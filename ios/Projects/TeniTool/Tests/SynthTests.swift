import Foundation
import Testing
import TeniVision
@testable import TeniToolKit

// MARK: - 노출 표기

@Suite("노출 파싱")
struct ExposureTests {

    @Test("분수 표기", arguments: [
        ("1/1000", 0.001), ("1/500", 0.002), ("1/60", 1.0 / 60), ("2/1000", 0.002),
    ])
    func 분수(_ input: String, _ expected: Double) {
        let exposure = Exposure(argument: input)
        #expect(exposure != nil)
        #expect(abs((exposure?.seconds ?? 0) - expected) < 1e-12)
        #expect(exposure?.label == input)
    }

    @Test("초 단위 직접 표기도 받는다")
    func 소수() {
        #expect(Exposure(argument: "0.001")?.seconds == 0.001)
    }

    @Test("잘못된 표기는 거부", arguments: ["", "1/0", "0/1000", "abc", "-1/1000", "1/"])
    func 거부(_ input: String) {
        #expect(Exposure(argument: input) == nil)
    }
}

// MARK: - 기하

@Suite("카메라 기하")
struct CameraTests {

    private let camera = SideOnCamera(
        widthPx: 1920, heightPx: 1080,
        distanceMeters: 6, heightMeters: 1.1, fieldOfView: 70, centerX: 0
    )

    @Test("공 지름은 BallGeometry가 단일 출처다")
    func 공_지름_위임() {
        let expected = BallGeometry.pixelDiameter(
            width: 1920, fieldOfView: 70, distanceMeters: 6
        )
        #expect(camera.ballDiameterPx == expected)
    }

    /// docs/02-설계/CAPTURE-PROTOCOL.md 5.1절 거리표
    @Test("프레임 폭이 프로토콜 표와 맞는다", arguments: [
        (5.0, 7.0), (6.0, 8.4), (8.0, 11.2), (10.0, 14.0), (12.0, 16.8),
    ])
    func 프레임_폭(_ distance: Double, _ expectedMeters: Double) {
        let c = SideOnCamera(
            widthPx: 1920, heightPx: 1080,
            distanceMeters: distance, heightMeters: 1.1, fieldOfView: 70, centerX: 0
        )
        let frameWidth = Double(c.widthPx) / c.pixelsPerMeter
        #expect(abs(frameWidth - expectedMeters) < 0.05)
    }

    @Test("렌즈 높이에 있는 점은 화면 수직 중앙에 온다")
    func 수직_중앙() {
        let p = camera.project(x: 0, y: 1.1)
        #expect(abs(p.py - 540) < 1e-9)
        #expect(abs(p.px - 960) < 1e-9)
    }

    @Test("월드 y가 커지면 이미지 y는 작아진다")
    func y축_뒤집힘() {
        let low = camera.project(x: 0, y: 0.5)
        let high = camera.project(x: 0, y: 2.0)
        #expect(high.py < low.py)
    }
}

// MARK: - 궤적

@Suite("궤적")
struct TrajectoryTests {

    private let trajectory = BallTrajectory(
        impactTime: 1.0, originX: 0, originY: 1.0,
        velocityX: 20, velocityY: 5
    )

    @Test("타구 전에는 공이 없다")
    func 타구_전() {
        #expect(trajectory.position(at: 0.99) == nil)
    }

    @Test("타구 순간은 타구 지점이다")
    func 타구_순간() {
        let p = trajectory.position(at: 1.0)
        #expect(p?.x == 0)
        #expect(p?.y == 1.0)
    }

    @Test("포물선이다 — 수직 가속이 중력과 같다")
    func 포물선() {
        let dt = 0.01
        let y0 = trajectory.position(afterImpact: 0).y
        let y1 = trajectory.position(afterImpact: dt).y
        let y2 = trajectory.position(afterImpact: 2 * dt).y
        let acceleration = (y2 - 2 * y1 + y0) / (dt * dt)
        #expect(abs(acceleration + BallTrajectory.gravity) < 1e-6)
    }

    @Test("지면 아래로 내려가면 끝난다")
    func 착지() {
        // y = 1 + 5t - 4.905t² = 0 → t ≈ 1.175
        #expect(trajectory.position(at: 1.0 + 1.0) != nil)
        #expect(trajectory.position(at: 1.0 + 1.3) == nil)
    }

    @Test("수평 발사면 속력이 중력으로 증가한다")
    func 속력() {
        let flat = BallTrajectory(
            impactTime: 0, originX: 0, originY: 5, velocityX: 10, velocityY: 0
        )
        #expect(abs(flat.speed(at: 0) - 10) < 1e-9)
        #expect(flat.speed(at: 0.5) > 10)
    }
}

// MARK: - sRGB

@Suite("sRGB 전달 함수")
struct SRGBTests {

    @Test("왕복이 동일하다", arguments: [0.0, 0.01, 0.04, 0.2, 0.5, 0.95, 1.0])
    func 왕복(_ value: Double) {
        #expect(abs(SRGB.fromLinear(SRGB.toLinear(value)) - value) < 1e-9)
    }

    @Test("중간 회색은 선형 0.5가 아니다")
    func 비선형() {
        // 이 차이가 선형 누적의 존재 이유다
        #expect(abs(SRGB.toLinear(0.5) - 0.2140) < 0.001)
    }
}

// MARK: - 블러 누적

@Suite("블러 누적")
struct BlurTests {

    private func plan(exposure: String, fps: Double, samples: Int? = nil) throws -> SynthPlan {
        var args = ["synth", "--out", "/dev/null/unused.mov", "--exposure", exposure, "--fps", "\(fps)"]
        if let samples { args += ["--blur-samples", "\(samples)"] }
        let command = try Synth.parse(Array(args.dropFirst()))
        return try SynthPlan(command: command)
    }

    /// docs/02-설계/CAPTURE-PROTOCOL.md 5.3절 번짐 표.
    /// 이 표가 틀리면 objectMinimumNormalizedRadius 파라미터가 통째로 틀어진다.
    /// 문서의 값은 반올림된 정수(1/60 행만 소수)다. 상대오차로 재면
    /// 6.35 → 6 같은 작은 값에서 반올림만으로 5.8%가 나온다.
    /// **반올림 오차로 판정한다** — 문서 표가 계산값을 올바르게 적었는가를 묻는 것이다.
    @Test("블러 길이가 프로토콜 5.3 표를 재현한다", arguments: [
        ("1/1000", 120.0, 6.3, 0.1),
        ("1/500", 120.0, 13.0, 0.5),
        ("1/250", 120.0, 25.0, 0.5),
        ("1/120", 120.0, 53.0, 0.5),
        ("1/60", 60.0, 106.0, 0.5),
    ])
    func 블러_길이(_ exposure: String, _ fps: Double, _ documented: Double, _ tolerance: Double) throws {
        let p = try plan(exposure: exposure, fps: fps)
        #expect(
            abs(p.referenceBlurLengthPx - documented) <= tolerance,
            "계산 \(p.referenceBlurLengthPx) vs 문서 \(documented)"
        )
    }

    @Test("하위 표본 수는 블러 길이 이상이다")
    func 표본_수() throws {
        for (exposure, fps) in [("1/1000", 120.0), ("1/250", 120.0), ("1/60", 60.0)] {
            let p = try plan(exposure: exposure, fps: fps)
            #expect(Double(p.blurSampleCount) >= p.referenceBlurLengthPx)
            #expect(p.blurSampleCount >= 8)
        }
    }

    @Test("하위 표본 시각이 노출 구간 안에 균일하게 놓인다")
    func 표본_시각() throws {
        let p = try plan(exposure: "1/1000", fps: 120, samples: 4)
        let times = p.sampleTimes(frame: 10)
        #expect(times.count == 4)
        let start = 10.0 / 120
        #expect(times.allSatisfy { $0 > start && $0 < start + p.exposureSeconds })
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { abs($0 - gaps[0]) < 1e-12 })
    }

    /// 선형 누적과 감마 누적은 **결과가 달라야** 한다.
    /// 같으면 선형화가 빠진 것이고, 물리적으로 틀린 블러가 나온다.
    @Test("선형 누적이 감마 평균과 다르다")
    func 선형_누적() {
        let renderer = FrameRenderer(
            width: 9, height: 9, backgroundLevel: 0.0, ballLevel: 1.0, noiseSigma: 0
        )
        var noise = NoiseGenerator(seed: 1)
        // 반 덮인 화소를 만든다 — 피복률 0.5
        let pixels = renderer.render(
            ballCenters: [(px: 4.5, py: 4.5), (px: 100, py: 100)],
            sampleCount: 2, ballRadiusPx: 3, noise: &noise
        )
        let center = Double(pixels[4 * 9 + 4]) / 255

        // 감마 공간에서 0과 1을 반씩 섞으면 0.5, 선형이면 0.735 근처
        #expect(abs(center - 0.5) > 0.1, "감마 평균으로 계산된 것 같습니다 (\(center))")
        #expect(abs(center - SRGB.fromLinear(0.5)) < 0.01)
    }

    @Test("노출이 프레임 간격보다 길면 거부한다")
    func 노출_상한() {
        #expect(throws: (any Error).self) {
            let command = try Synth.parse(["--out", "/tmp/x.mov", "--exposure", "1/60", "--fps", "120"])
            try command.validate()
        }
    }
}

// MARK: - 렌더 결과 실측

@Suite("렌더 결과 실측")
struct RenderMeasurementTests {

    /// 가로 해상도 1920은 유지한다 — 프로토콜 5.1/5.3 표의 기준이다.
    /// 세로와 길이는 줄인다. 공은 화면 중앙 근처에만 있고, 프레임을 수백 장
    /// 렌더하면 테스트가 분 단위로 늘어진다.
    private func makePlan(_ extra: [String]) throws -> SynthPlan {
        let command = try Synth.parse(
            ["--out", "/tmp/unused.mov", "--height", "256", "--hits", "1", "--hit-interval", "0.15"]
                + extra
        )
        return try SynthPlan(command: command)
    }

    /// 픽셀을 직접 재서 이론값과 대조한다. 계산값을 출력하는 것과
    /// 영상이 실제로 그렇게 그려지는 것은 다른 문제다.
    ///
    /// **임계값으로 streak 양끝을 찾는 방법은 쓰지 않는다.** 블러의 양끝은
    /// 밝기가 0으로 매끄럽게 수렴하므로 어떤 임계값을 잡아도 꼬리가 잘리고,
    /// 그 편향이 표본 수에 따라 달라진다 (실측: 표본 8·13·26에서 각각
    /// 1.7·3.0·5.7 px 부족). 대신 **밝기를 가중치로 쓴 2차 모멘트**를 쓴다.
    ///
    /// 반지름 r의 원판을 길이 L의 박스로 합성곱하면 x축 분산은
    /// `r²/4 + L²/12`이므로 L을 역산할 수 있다. 임계값이 없다.
    private struct Marginal {
        let centerX: Double
        let centerY: Double
        let blurLengthPx: Double
    }

    private func measureMarginal(
        _ pixels: [UInt8], width: Int, height: Int,
        background: Double, ballLevel: Double, ballRadiusPx: Double
    ) -> Marginal? {
        let backgroundLinear = SRGB.toLinear(background)
        let span = SRGB.toLinear(ballLevel) - backgroundLinear
        guard span > 0 else { return nil }

        var columns = [Double](repeating: 0, count: width)
        var rows = [Double](repeating: 0, count: height)
        var total = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let linear = SRGB.toLinear(Double(pixels[y * width + x]) / 255)
                let fraction = max(0, (linear - backgroundLinear) / span)
                guard fraction > 0 else { continue }
                columns[x] += fraction
                rows[y] += fraction
                total += fraction
            }
        }
        guard total > 0 else { return nil }

        func moments(_ profile: [Double]) -> (mean: Double, variance: Double) {
            var mean = 0.0
            for (index, weight) in profile.enumerated() {
                mean += (Double(index) + 0.5) * weight
            }
            mean /= total
            var variance = 0.0
            for (index, weight) in profile.enumerated() {
                let d = Double(index) + 0.5 - mean
                variance += d * d * weight
            }
            return (mean, variance / total)
        }

        let x = moments(columns)
        let y = moments(rows)
        // 원판의 x축 분산은 r²/4. 나머지가 블러 박스의 L²/12이다.
        let discVariance = ballRadiusPx * ballRadiusPx / 4
        let boxVariance = max(0, x.variance - discVariance)
        return Marginal(
            centerX: x.mean,
            centerY: y.mean,
            blurLengthPx: (12 * boxVariance).squareRoot()
        )
    }

    @Test("렌더된 블러 길이가 이론값과 일치한다", arguments: ["1/1000", "1/500", "1/250"])
    func 블러_실측(_ exposure: String) throws {
        let p = try makePlan(["--exposure", exposure, "--fps", "120", "--noise", "0"])
        let output = p.render()
        let impact = output.groundTruth.groundTruth.impactFrames[0]
        // 타구 직후 프레임 — 속력이 거의 초기값이다
        let frame = output.frames[impact + 1]
        let measured = try #require(
            measureMarginal(
                frame,
                width: p.camera.widthPx, height: p.camera.heightPx,
                background: 0.35, ballLevel: 0.95,
                ballRadiusPx: p.camera.ballDiameterPx / 2
            )
        )
        let expected = p.referenceBlurLengthPx
        let error = abs(measured.blurLengthPx - expected) / expected
        #expect(
            error < 0.10,
            "\(exposure): 실측 \(measured.blurLengthPx) vs 이론 \(expected), 오차 \(error)"
        )
    }

    @Test("정답 좌표가 렌더된 공의 무게중심과 일치한다")
    func 정답_좌표() throws {
        // 블러를 거의 없애면 정답 중심과 무게중심이 같아야 한다
        let p = try makePlan([
            "--exposure", "1/20000", "--fps", "120", "--noise", "0", "--blur-samples", "1",
        ])
        let output = p.render()
        let impact = output.groundTruth.groundTruth.impactFrames[0]
        let truth = try #require(
            output.groundTruth.groundTruth.ballCenters.first { $0.frame == impact + 2 }
        )
        let measured = try #require(
            measureMarginal(
                output.frames[impact + 2],
                width: p.camera.widthPx, height: p.camera.heightPx,
                background: 0.35, ballLevel: 0.95,
                ballRadiusPx: p.camera.ballDiameterPx / 2
            )
        )
        #expect(abs(measured.centerX - truth.x) < 1.0, "x 실측 \(measured.centerX) vs 정답 \(truth.x)")
        #expect(abs(measured.centerY - truth.y) < 1.0, "y 실측 \(measured.centerY) vs 정답 \(truth.y)")
    }

    @Test("정답 JSON의 blurLengthPx가 속도 × 노출과 맞는다")
    func blur_역산() throws {
        let p = try makePlan(["--exposure", "1/500", "--fps", "120", "--noise", "0"])
        let output = p.render()
        let centers = output.groundTruth.groundTruth.ballCenters
        #expect(!centers.isEmpty)
        for center in centers.prefix(20) {
            // BlurBall Eq. 8: 블러 길이 = 속도(px/s) × 노출
            let expected = center.speedMetersPerSecond * p.camera.pixelsPerMeter * p.exposureSeconds
            // 하위 표본이 구간 내부에 놓이므로 양 끝 반 칸이 빠진다
            let ratio = center.blurLengthPx / expected
            #expect(ratio > 0.8 && ratio <= 1.01, "프레임 \(center.frame): \(ratio)")
        }
    }

    @Test("같은 시드는 같은 결과를 낸다")
    func 재현성() throws {
        let args = ["--exposure", "1/1000", "--fps", "120", "--seed", "42"]
        let a = try makePlan(args).render()
        let b = try makePlan(args).render()
        #expect(a.frames == b.frames)
    }

    @Test("다른 시드는 노이즈가 달라진다")
    func 시드_차이() throws {
        let base = ["--exposure", "1/1000", "--fps", "120", "--noise", "0.05"]
        let a = try makePlan(base + ["--seed", "1"]).render()
        let b = try makePlan(base + ["--seed", "2"]).render()
        #expect(a.frames != b.frames)
    }

    /// 간격 1.0초는 궤적 지속 시간(1.33초)보다 짧아 두 공이 동시에 보인다.
    /// 이 상황에서 두 버그가 있었다 — 표본 수를 위치 개수에서 유추해 공이
    /// 절반 밝기로 그려졌고, 정답에는 마지막 궤적 하나만 기록됐다.
    @Test("궤적이 겹쳐도 공 밝기와 정답이 온전하다")
    func 궤적_겹침() throws {
        let command = try Synth.parse([
            "--out", "/tmp/unused.mov", "--height", "256", "--noise", "0",
            "--fps", "120", "--hits", "2", "--hit-interval", "1.0",
            "--exposure", "1/1000",
        ])
        let p = try SynthPlan(command: command)
        let output = p.render()
        let centers = output.groundTruth.groundTruth.ballCenters

        // 두 공이 동시에 보이는 프레임이 있어야 한다
        let grouped = Dictionary(grouping: centers, by: \.frame)
        let overlapping = grouped.filter { $0.value.count > 1 }
        #expect(!overlapping.isEmpty, "겹치는 프레임이 없습니다 — 전제가 깨졌습니다")

        // 그 프레임에는 서로 다른 타구가 기록되어야 한다
        for (_, group) in overlapping {
            #expect(Set(group.map(\.hitIndex)).count == group.count)
        }

        // 겹치는 프레임의 공 밝기가 겹치지 않는 프레임과 같아야 한다
        let overlapFrame = try #require(overlapping.keys.sorted().first)
        let soloFrame = try #require(
            grouped.filter { $0.value.count == 1 }.keys.sorted().first
        )
        func peak(_ frame: Int) -> UInt8 { output.frames[frame].max() ?? 0 }
        let difference = abs(Int(peak(overlapFrame)) - Int(peak(soloFrame)))
        #expect(
            difference <= 2,
            "겹침 프레임 최대 밝기 \(peak(overlapFrame)) vs 단독 \(peak(soloFrame)) — 표본 수가 틀어진 것 같습니다"
        )
    }

    @Test("타구 프레임이 fps에서 올바르게 나온다")
    func 타구_프레임() throws {
        let command = try Synth.parse(
            ["--out", "/tmp/unused.mov", "--height", "256", "--fps", "120",
             "--hits", "3", "--hit-interval", "1.0"]
        )
        let p = try SynthPlan(command: command)
        let frames = p.render().groundTruth.groundTruth.impactFrames
        // impactTime = 0.3 + index * 1.0
        #expect(frames == [36, 156, 276])
    }
}
