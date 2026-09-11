import Foundation

/// 합성 영상의 정답. docs/02-설계/CAPTURE-PROTOCOL.md 5.5절의 기록 포맷을
/// **상위 호환**으로 확장한다 — `condition`·`capture`·`params`·`groundTruth`를
/// 그대로 두고 `synthetic`을 더한다. #7 분석 도구와 #9 집계가 같은 키를 읽는다.
public struct GroundTruth: Codable, Sendable {
    public let clipId: String
    public let condition: Condition
    public let capture: Capture
    public let groundTruth: Truth
    public let synthetic: Synthetic

    public struct Condition: Codable, Sendable {
        public let location: String
        public let light: String
        public let background: String
    }

    public struct Capture: Codable, Sendable {
        public let fps: Double
        public let resolution: String
        public let exposureDuration: String
        public let distanceM: Double
        public let heightM: Double
        public let videoFieldOfView: Double
    }

    public struct Truth: Codable, Sendable {
        /// 5.5절이 요구하는 분모
        public let impactFrames: [Int]
        /// 프레임별 공 중심. 공이 화면에 없는 프레임은 생략한다.
        public let ballCenters: [BallCenter]
    }

    public struct BallCenter: Codable, Sendable {
        public let frame: Int
        public let x: Double
        public let y: Double
        /// 이 프레임의 노출 구간에서 공이 이동한 거리 (px).
        /// BlurBall Eq. 8의 역산 검증에 쓴다.
        public let blurLengthPx: Double
        public let speedMetersPerSecond: Double
    }

    public struct Synthetic: Codable, Sendable {
        public let generator: String
        public let ballDiameterPx: Double
        public let pixelsPerMeter: Double
        public let blurSamplesPerFrame: Int
        public let noiseSigma: Double
        public let seed: UInt64
        /// 롤링 셔터는 구현하지 않았다. 실영상과의 첫 대조 항목이다.
        public let rollingShutter: Bool
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
