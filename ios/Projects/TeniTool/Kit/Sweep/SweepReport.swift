import Foundation

/// 스윕 결과. #9 이후 사람이 읽고 파라미터를 고르는 근거다.
public struct SweepReport: Codable, Sendable {

    public enum Mode: String, Codable, Sendable {
        /// 합성 영상 — **게이트 값이 아니다**
        case synthetic
        /// 실영상 — 게이트 판정에 쓸 수 있다
        case realFootage
    }

    public let mode: Mode
    public let generatedAt: Date
    public let results: [Entry]

    public struct Entry: Codable, Sendable {
        public let condition: Condition
        public let metrics: DetectionMetrics
        public let clipCount: Int

        public init(condition: Condition, metrics: DetectionMetrics, clipCount: Int) {
            self.condition = condition
            self.metrics = metrics
            self.clipCount = clipCount
        }
    }

    /// `SweepPlan.Condition`의 직렬화 형태
    public struct Condition: Codable, Sendable {
        public let axis: String
        public let exposure: String
        public let distanceM: Double
        public let trajectoryLength: Int
        public let minRadius: Double
        public let maxRadius: Double

        public init(_ condition: SweepPlan.Condition) {
            self.axis = condition.axis
            self.exposure = condition.exposure
            self.distanceM = condition.distanceMeters
            self.trajectoryLength = condition.trajectoryLength
            self.minRadius = condition.minRadius
            self.maxRadius = condition.maxRadius
        }
    }

    public init(mode: Mode, generatedAt: Date, results: [Entry]) {
        self.mode = mode
        self.generatedAt = generatedAt
        self.results = results
    }

    /// recall이 가장 높은 조건. **게이트 판정 기준이 recall이기 때문이다.**
    /// 동률이면 precision이 높은 쪽을 고른다 — 헛검출이 적은 것이 낫다.
    public var best: Entry? {
        results.max {
            ($0.metrics.recall, $0.metrics.precision) < ($1.metrics.recall, $1.metrics.precision)
        }
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
