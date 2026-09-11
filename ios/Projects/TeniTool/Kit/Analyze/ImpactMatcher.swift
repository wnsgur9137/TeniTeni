import Foundation

/// 검출 궤적을 실제 타구에 대응시킨다.
///
/// 기준은 docs/02-설계/CAPTURE-PROTOCOL.md 5.5절이 정했다 —
/// **임팩트 프레임 ±3프레임 내에 시작하고 0.2초 이상 이어진 궤적.**
/// "궤적 하나라도 잡히면 성공"으로 하면 임팩트와 무관한 짧은 궤적이
/// 검출률을 부풀린다.
public enum ImpactMatcher {

    /// 임팩트 프레임과 궤적 시작 프레임의 허용 차이
    public static let frameTolerance = 3
    /// 궤적이 이어져야 하는 최소 시간 (초)
    public static let minimumDurationSeconds = 0.2

    public struct Candidate: Sendable {
        public let startFrame: Int
        public let durationSec: Double

        public init(startFrame: Int, durationSec: Double) {
            self.startFrame = startFrame
            self.durationSec = durationSec
        }
    }

    public struct Outcome: Sendable {
        /// 후보 순서대로의 매칭 결과. nil이면 오검출.
        public let matches: [Int?]
        public let hits: Int
        public let falsePositives: Int

        public var total: Int { hits + falsePositives }
    }

    /// - Parameters:
    ///   - candidates: 검출된 궤적들
    ///   - impactFrames: 정답 타구 프레임
    ///
    /// 한 임팩트에 여러 궤적이 걸리면 **가장 가까운 하나만** 매칭한다.
    /// 나머지는 오검출로 센다 — 그러지 않으면 한 타구를 여러 번 세어
    /// 검출률이 부풀려진다.
    public static func match(
        candidates: [Candidate],
        impactFrames: [Int]
    ) -> Outcome {
        var claimedBy: [Int: Int] = [:]   // 임팩트 프레임 → 후보 인덱스
        var bestDistance: [Int: Int] = [:]

        for (index, candidate) in candidates.enumerated() {
            guard candidate.durationSec >= minimumDurationSeconds else { continue }

            // 허용 범위 안에서 가장 가까운 임팩트를 찾는다
            var nearest: (frame: Int, distance: Int)?
            for impact in impactFrames {
                let distance = abs(candidate.startFrame - impact)
                guard distance <= frameTolerance else { continue }
                if nearest == nil || distance < nearest!.distance {
                    nearest = (impact, distance)
                }
            }
            guard let nearest else { continue }

            // 이미 더 가까운 후보가 차지했으면 양보한다
            if let existing = bestDistance[nearest.frame], existing <= nearest.distance {
                continue
            }
            claimedBy[nearest.frame] = index
            bestDistance[nearest.frame] = nearest.distance
        }

        var matches = [Int?](repeating: nil, count: candidates.count)
        for (impact, index) in claimedBy {
            matches[index] = impact
        }

        let hits = claimedBy.count
        let falsePositives = candidates.count - hits
        return Outcome(matches: matches, hits: hits, falsePositives: falsePositives)
    }

    /// 검출률 = 매칭된 타구 수 / 실제 타구 수.
    /// 분모는 검출 개수가 아니라 **정답 타구 수**다.
    public static func detectionRate(hits: Int, impactCount: Int) -> Double {
        guard impactCount > 0 else { return 0 }
        return Double(hits) / Double(impactCount)
    }
}
