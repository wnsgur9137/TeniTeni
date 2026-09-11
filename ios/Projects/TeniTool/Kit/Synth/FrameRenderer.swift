import Foundation

/// 한 프레임을 그린다. 노출 구간 안에서 하위 표본 N장을 **선형 공간에서**
/// 누적해 모션 블러를 만든다.
///
/// 감마 값을 그대로 평균하면 물리적으로 틀린 블러가 나온다. 센서는 빛을
/// 선형으로 적분하므로 선형화 → 평균 → 감마 순서를 지켜야 한다.
/// 근거: docs/08-레퍼런스/ml/MotionBlur.md 2절
public struct FrameRenderer {

    public let width: Int
    public let height: Int
    /// 배경·공의 sRGB 밝기 (0~1)
    public let backgroundLevel: Double
    public let ballLevel: Double

    /// 배경에 섞는 가우시안 노이즈의 표준편차 (sRGB 단위, 0이면 없음)
    public let noiseSigma: Double

    private let backgroundLinear: Double
    private let ballLinear: Double
    /// 공이 닿지 않은 화소의 최종 값. 화면 대부분이 여기 해당하므로
    /// 미리 구해두면 프레임마다 2백만 번의 pow()를 건너뛴다.
    private let backgroundByte: UInt8

    public init(width: Int, height: Int, backgroundLevel: Double, ballLevel: Double, noiseSigma: Double) {
        self.width = width
        self.height = height
        self.backgroundLevel = backgroundLevel
        self.ballLevel = ballLevel
        self.noiseSigma = noiseSigma
        self.backgroundLinear = SRGB.toLinear(backgroundLevel)
        self.ballLinear = SRGB.toLinear(ballLevel)
        self.backgroundByte = UInt8(clamping: Int((min(max(backgroundLevel, 0), 1) * 255).rounded()))
    }

    /// 하위 표본들의 공 위치를 받아 8bit 그레이 버퍼를 만든다.
    ///
    /// 배경이 균일하므로 표본마다 전체 화면을 합성할 필요가 없다.
    /// 각 화소의 **피복률 합**만 모으면
    /// `L = bg + (Σcov / N) · (ball − bg)` 로 정확히 같은 결과가 나온다.
    public func render(
        ballCenters: [(px: Double, py: Double)],
        ballRadiusPx: Double,
        noise: inout NoiseGenerator
    ) -> [UInt8] {
        var coverage = [Double](repeating: 0, count: width * height)
        let sampleCount = max(1, ballCenters.count)

        for center in ballCenters {
            accumulateDisc(center: center, radius: ballRadiusPx, into: &coverage)
        }

        var pixels = [UInt8](repeating: backgroundByte, count: width * height)
        let delta = ballLinear - backgroundLinear
        let inverseSamples = 1 / Double(sampleCount)

        for i in 0..<pixels.count {
            let raw = coverage[i]
            // 공이 전혀 닿지 않았고 노이즈도 없으면 미리 구한 배경 값이 답이다
            if raw == 0 && noiseSigma == 0 { continue }

            var value: Double
            if raw == 0 {
                value = backgroundLevel
            } else {
                let fraction = min(1.0, raw * inverseSamples)
                value = SRGB.fromLinear(backgroundLinear + fraction * delta)
            }
            if noiseSigma > 0 {
                value += noise.nextGaussian() * noiseSigma
            }
            pixels[i] = UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
        }
        return pixels
    }

    /// 원 하나의 피복률을 더한다. 경계는 화소 중심과의 거리로 1px 폭
    /// 선형 보간해 앤티앨리어싱한다 — 블러 길이 측정에 소수점 정확도가
    /// 필요하므로 경계를 계단으로 두면 안 된다.
    private func accumulateDisc(
        center: (px: Double, py: Double),
        radius: Double,
        into coverage: inout [Double]
    ) {
        guard radius > 0 else { return }
        let minX = max(0, Int((center.px - radius - 1).rounded(.down)))
        let maxX = min(width - 1, Int((center.px + radius + 1).rounded(.up)))
        let minY = max(0, Int((center.py - radius - 1).rounded(.down)))
        let maxY = min(height - 1, Int((center.py + radius + 1).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            let dy = Double(y) + 0.5 - center.py
            for x in minX...maxX {
                let dx = Double(x) + 0.5 - center.px
                let distance = (dx * dx + dy * dy).squareRoot()
                let value = min(max(radius + 0.5 - distance, 0), 1)
                if value > 0 {
                    coverage[y * width + x] += value
                }
            }
        }
    }
}

/// sRGB 전달 함수. 표준 정의를 그대로 쓴다.
public enum SRGB {
    public static func toLinear(_ value: Double) -> Double {
        let v = min(max(value, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    public static func fromLinear(_ value: Double) -> Double {
        let v = min(max(value, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

/// 재현 가능한 노이즈. 시드를 고정해야 같은 인자로 같은 영상이 나온다 —
/// 파라미터 스윕(#9)에서 노이즈가 달라지면 조건 비교가 무의미해진다.
public struct NoiseGenerator {
    private var state: UInt64
    private var spare: Double?

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    private mutating func nextUniform() -> Double {
        // splitmix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Box-Muller
    public mutating func nextGaussian() -> Double {
        if let value = spare {
            spare = nil
            return value
        }
        var u1 = nextUniform()
        if u1 < 1e-12 { u1 = 1e-12 }
        let u2 = nextUniform()
        let magnitude = (-2 * log(u1)).squareRoot()
        spare = magnitude * sin(2 * .pi * u2)
        return magnitude * cos(2 * .pi * u2)
    }
}
