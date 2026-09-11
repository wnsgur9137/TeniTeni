import Foundation

/// 사람이 찍은 임팩트 프레임. `teni analyze --ground-truth`가 읽는 포맷이다.
///
/// `GroundTruth`(teni synth 출력)와 **키 구조를 맞춘다** — 분석 도구가
/// 합성 정답과 수동 라벨을 구분 없이 받아야 한다.
public struct LabelSet: Codable, Sendable {
    public let clipId: String
    public let condition: GroundTruth.Condition
    public let capture: GroundTruth.Capture
    public let groundTruth: Truth
    public let labeling: Labeling

    public struct Truth: Codable, Sendable {
        /// 프로토콜 5.5의 분모. Action Spotting — 구간이 아니라 단일 프레임이다.
        public let impactFrames: [Int]

        public init(impactFrames: [Int]) {
            self.impactFrames = impactFrames
        }
    }

    public struct Labeling: Codable, Sendable {
        public let labeledAt: Date
        /// 몇 번째 라벨링인가. 자기 일치도 측정에 쓴다.
        public let pass: Int
        public let note: String?

        public init(labeledAt: Date, pass: Int, note: String?) {
            self.labeledAt = labeledAt
            self.pass = pass
            self.note = note
        }
    }

    public init(
        clipId: String,
        condition: GroundTruth.Condition,
        capture: GroundTruth.Capture,
        groundTruth: Truth,
        labeling: Labeling
    ) {
        self.clipId = clipId
        self.condition = condition
        self.capture = capture
        self.groundTruth = groundTruth
        self.labeling = labeling
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// 두 라벨링의 일치도.
///
/// 게이트 검출률의 분모를 사람이 만든다. **그 사람이 얼마나 정확한지
/// 모르면 검출률이 낮게 나왔을 때 도구를 탓하게 된다.**
/// 근거: docs/08-레퍼런스/ml/EventAnnotation.md 2절
public struct Agreement: Sendable {

    /// 프로토콜 5.5의 매칭 허용오차. 이 값을 넘으면 기준이 사람의
    /// 정밀도보다 엄격하다는 뜻이다.
    public static let toleranceFrames = 3

    public struct Pair: Sendable {
        public let first: Int
        public let second: Int
        public var difference: Int { abs(first - second) }
    }

    public let pairs: [Pair]
    /// 짝을 찾지 못한 프레임 — 한쪽에서만 센 타구다
    public let unmatchedFirst: [Int]
    public let unmatchedSecond: [Int]

    public var meanAbsoluteDifference: Double {
        guard !pairs.isEmpty else { return 0 }
        return Double(pairs.reduce(0) { $0 + $1.difference }) / Double(pairs.count)
    }

    public var maxDifference: Int {
        pairs.map(\.difference).max() ?? 0
    }

    /// 모든 짝이 허용오차 안에 있고 누락이 없는가
    public var withinTolerance: Bool {
        unmatchedFirst.isEmpty && unmatchedSecond.isEmpty
            && pairs.allSatisfy { $0.difference <= Self.toleranceFrames }
    }

    /// 가까운 것끼리 짝짓는다. 탐색 폭은 허용오차보다 넉넉히 둬야
    /// "많이 어긋난 짝"도 드러난다 — 좁게 잡으면 전부 미매칭이 되어
    /// 얼마나 어긋났는지 알 수 없다.
    public static func compare(
        _ first: [Int],
        _ second: [Int],
        searchWindow: Int = 30
    ) -> Agreement {
        var remaining = second.sorted()
        var pairs: [Pair] = []
        var unmatchedFirst: [Int] = []

        for frame in first.sorted() {
            guard let index = remaining.enumerated()
                .filter({ abs($0.element - frame) <= searchWindow })
                .min(by: { abs($0.element - frame) < abs($1.element - frame) })?
                .offset
            else {
                unmatchedFirst.append(frame)
                continue
            }
            pairs.append(Pair(first: frame, second: remaining[index]))
            remaining.remove(at: index)
        }

        return Agreement(
            pairs: pairs,
            unmatchedFirst: unmatchedFirst,
            unmatchedSecond: remaining
        )
    }
}
