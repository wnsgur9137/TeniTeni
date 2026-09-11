import Foundation

/// 분석 결과. docs/02-설계/CAPTURE-PROTOCOL.md 5.5절의 기록 포맷이다.
/// #9 집계 스크립트가 이 키를 읽는다.
public struct DetectionReport: Codable, Sendable {
    public let clipId: String
    public let condition: Condition
    public let capture: Capture
    public let params: Params
    public let groundTruth: Truth?
    public let detected: [Detection]
    public let result: Result?

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
    }

    public struct Params: Codable, Sendable {
        public let trajectoryLength: Int
        public let minRadius: Double
        public let maxRadius: Double
    }

    public struct Truth: Codable, Sendable {
        public let impactFrames: [Int]
    }

    public struct Detection: Codable, Sendable {
        public let startFrame: Int
        public let durationSec: Double
        /// 매칭된 임팩트 프레임. 없으면 오검출이다.
        public let matchedImpact: Int?
        public let movingAverageRadius: Double
        /// **공의 물리적 크기가 아니다.** movingAverageRadius를 픽셀로 환산한
        /// 값이고, 그것은 블러를 포함한 바운딩 원의 반지름이다.
        /// 실측: 1/1000s에서 공 15.31px인데 27.66px이 나온다
        /// (docs/08-레퍼런스/ml/DetectTrajectories.md 6절).
        public let detectedDiameterPx: Double
        /// 검출점 개수. trajectoryLength 이상이어야 궤적이 확정된다.
        public let pointCount: Int
        public let confidence: Double
    }

    public struct Result: Codable, Sendable {
        public let hits: Int
        public let total: Int
        public let detectionRate: Double
        public let falsePositives: Int
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
