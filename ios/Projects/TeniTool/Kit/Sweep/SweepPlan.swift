import Foundation

/// 스윕할 조건들을 만든다.
///
/// **축별 1차원 스윕(OFAT)이다.** 기본값에서 한 축씩 움직인다. 4축 각 4값을
/// 전수 조합하면 256조합인데 합성·분석 시간이 감당되지 않는다.
/// 근거: docs/07-기획/SPEC-0009-parameter-sweep.md 구현 선택지 1
public struct SweepPlan: Sendable {

    /// 스윕 한 칸. 영상을 바꾸는 축과 분석만 바꾸는 축이 나뉜다.
    public struct Condition: Sendable, Hashable {
        /// 영상을 결정하는 축 — 바뀌면 새로 합성해야 한다
        public let exposure: String
        public let distanceMeters: Double
        /// 분석만 바꾸는 축 — 같은 영상으로 돈다
        public let trajectoryLength: Int
        public let minRadius: Double
        public let maxRadius: Double

        /// 어느 축을 움직여 만든 조건인가. 표에서 묶어 보여준다.
        public let axis: String

        public init(
            exposure: String, distanceMeters: Double,
            trajectoryLength: Int, minRadius: Double, maxRadius: Double,
            axis: String
        ) {
            self.exposure = exposure
            self.distanceMeters = distanceMeters
            self.trajectoryLength = trajectoryLength
            self.minRadius = minRadius
            self.maxRadius = maxRadius
            self.axis = axis
        }

        /// 합성 영상을 공유할 수 있는가를 정하는 키.
        /// 분석 파라미터는 영상을 바꾸지 않으므로 제외한다.
        public var videoKey: String {
            "\(exposure.replacingOccurrences(of: "/", with: "_"))_\(Int(distanceMeters))m"
        }
    }

    public struct Baseline: Sendable {
        public let exposure: String
        public let distanceMeters: Double
        public let trajectoryLength: Int
        public let minRadius: Double
        public let maxRadius: Double

        public init(
            exposure: String = "1/1000",
            distanceMeters: Double = 6,
            trajectoryLength: Int = 5,
            minRadius: Double = 0.002,
            maxRadius: Double = 0.015
        ) {
            self.exposure = exposure
            self.distanceMeters = distanceMeters
            self.trajectoryLength = trajectoryLength
            self.minRadius = minRadius
            self.maxRadius = maxRadius
        }

        func condition(axis: String) -> Condition {
            Condition(
                exposure: exposure, distanceMeters: distanceMeters,
                trajectoryLength: trajectoryLength,
                minRadius: minRadius, maxRadius: maxRadius,
                axis: axis
            )
        }
    }

    /// 축별로 값을 바꾼 조건 목록. **기준점은 한 번만 넣는다.**
    public static func conditions(
        baseline: Baseline,
        exposures: [String],
        distances: [Double],
        trajectoryLengths: [Int],
        maxRadii: [Double]
    ) -> [Condition] {
        var result: [Condition] = [baseline.condition(axis: "기준")]
        var seen: Set<Condition> = [result[0]]

        func add(_ condition: Condition) {
            // 기준값과 같은 조건은 중복이다. 축만 다르고 내용이 같으면 버린다.
            guard !seen.contains(where: { $0.sameParameters(as: condition) }) else { return }
            seen.insert(condition)
            result.append(condition)
        }

        for value in exposures {
            add(Condition(
                exposure: value, distanceMeters: baseline.distanceMeters,
                trajectoryLength: baseline.trajectoryLength,
                minRadius: baseline.minRadius, maxRadius: baseline.maxRadius,
                axis: "노출"
            ))
        }
        for value in distances {
            add(Condition(
                exposure: baseline.exposure, distanceMeters: value,
                trajectoryLength: baseline.trajectoryLength,
                minRadius: baseline.minRadius, maxRadius: baseline.maxRadius,
                axis: "거리"
            ))
        }
        for value in trajectoryLengths {
            add(Condition(
                exposure: baseline.exposure, distanceMeters: baseline.distanceMeters,
                trajectoryLength: value,
                minRadius: baseline.minRadius, maxRadius: baseline.maxRadius,
                axis: "궤적 길이"
            ))
        }
        for value in maxRadii {
            add(Condition(
                exposure: baseline.exposure, distanceMeters: baseline.distanceMeters,
                trajectoryLength: baseline.trajectoryLength,
                minRadius: baseline.minRadius, maxRadius: value,
                axis: "최대 반지름"
            ))
        }
        return result
    }
}

extension SweepPlan.Condition {
    /// 축 이름을 빼고 파라미터만 비교한다.
    func sameParameters(as other: Self) -> Bool {
        exposure == other.exposure
            && distanceMeters == other.distanceMeters
            && trajectoryLength == other.trajectoryLength
            && minRadius == other.minRadius
            && maxRadius == other.maxRadius
    }
}
