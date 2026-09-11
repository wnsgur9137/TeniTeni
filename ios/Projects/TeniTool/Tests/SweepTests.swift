import Foundation
import Testing
@testable import TeniToolKit

// MARK: - 지표

/// 우리 "검출률"은 표준의 recall이다. 게이트가 recall로만 판정하므로
/// **precision을 함께 내지 않으면 헛검출 많은 설정이 "최적"으로 뽑힌다.**
/// 근거: docs/08-레퍼런스/ml/DetectionMetrics.md
@Suite("검출 지표")
struct DetectionMetricsTests {

    @Test("완벽한 검출")
    func 완벽() {
        let m = DetectionMetrics(truePositives: 10, falsePositives: 0, falseNegatives: 0)
        #expect(m.precision == 1.0)
        #expect(m.recall == 1.0)
        #expect(m.f1 == 1.0)
        #expect(!m.precisionIsLow)
    }

    /// 이것이 게이트의 사각이다. recall 75%로 통과하지만 타구 하나에
    /// 헛검출 셋이 붙는다.
    @Test("recall은 높고 precision은 낮은 설정")
    func 헛검출_많음() {
        let m = DetectionMetrics(truePositives: 15, falsePositives: 45, falseNegatives: 5)
        #expect(m.recall == 0.75)
        #expect(m.precision == 0.25)
        #expect(m.verdict == .pass, "게이트는 recall만 보므로 통과한다")
        #expect(m.precisionIsLow, "그러나 경고는 떠야 한다")
    }

    @Test("검출이 없으면 전부 0")
    func 검출_없음() {
        let m = DetectionMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 10)
        #expect(m.precision == 0)
        #expect(m.recall == 0)
        #expect(m.f1 == 0)
        // 검출 자체가 없으면 precision 경고는 의미가 없다
        #expect(!m.precisionIsLow)
    }

    @Test("F1은 조화평균이다")
    func 조화평균() {
        let m = DetectionMetrics(truePositives: 5, falsePositives: 5, falseNegatives: 5)
        #expect(m.precision == 0.5)
        #expect(m.recall == 0.5)
        #expect(m.f1 == 0.5)

        let skewed = DetectionMetrics(truePositives: 9, falsePositives: 1, falseNegatives: 9)
        #expect(abs(skewed.precision - 0.9) < 1e-9)
        #expect(abs(skewed.recall - 0.5) < 1e-9)
        // 산술평균 0.7보다 낮아야 한다
        #expect(skewed.f1 < 0.7)
        #expect(abs(skewed.f1 - 2 * 0.9 * 0.5 / 1.4) < 1e-9)
    }

    /// 프로토콜 5.5의 판정 경계. 이 숫자가 바뀌면 게이트가 바뀐다.
    @Test("판정 경계", arguments: [
        (100, 0, 0, DetectionMetrics.Verdict.pass),      // 100%
        (70, 0, 30, DetectionMetrics.Verdict.pass),      // 정확히 70%
        (699, 0, 301, DetectionMetrics.Verdict.tune),    // 69.9%
        (50, 0, 50, DetectionMetrics.Verdict.tune),      // 정확히 50%
        (499, 0, 501, DetectionMetrics.Verdict.redesign),// 49.9%
        (0, 0, 100, DetectionMetrics.Verdict.redesign),  // 0%
    ])
    func 판정_경계(_ tp: Int, _ fp: Int, _ fn: Int, _ expected: DetectionMetrics.Verdict) {
        let m = DetectionMetrics(truePositives: tp, falsePositives: fp, falseNegatives: fn)
        #expect(m.verdict == expected, "recall \(m.recall)")
    }
}

// MARK: - 조건 생성

@Suite("스윕 조건")
struct SweepPlanTests {

    private let baseline = SweepPlan.Baseline()

    @Test("기준값이 첫 조건이다")
    func 기준_우선() {
        let conditions = SweepPlan.conditions(
            baseline: baseline, exposures: [], distances: [],
            trajectoryLengths: [], maxRadii: []
        )
        #expect(conditions.count == 1)
        #expect(conditions[0].axis == "기준")
        #expect(conditions[0].exposure == "1/1000")
    }

    /// 전수 조합이 아니라 축별 1차원이다. 4축 각 3값이면 전수는 81조합인데
    /// OFAT은 기준 1 + 축별 추가분이다.
    @Test("축별 1차원 스윕이다")
    func OFAT() {
        let conditions = SweepPlan.conditions(
            baseline: baseline,
            exposures: ["1/1000", "1/500", "1/250"],
            distances: [5, 6, 8],
            trajectoryLengths: [5, 7, 10],
            maxRadii: [0.008, 0.015, 0.030]
        )
        // 기준 1 + 노출 2(1/1000은 기준과 같음) + 거리 2 + 길이 2 + 반지름 2 = 9
        #expect(conditions.count == 9, "전수 조합(81)이 아니어야 한다")

        // 한 조건에서 축 하나만 기준과 다르다
        for condition in conditions.dropFirst() {
            var differences = 0
            if condition.exposure != baseline.exposure { differences += 1 }
            if condition.distanceMeters != baseline.distanceMeters { differences += 1 }
            if condition.trajectoryLength != baseline.trajectoryLength { differences += 1 }
            if condition.maxRadius != baseline.maxRadius { differences += 1 }
            #expect(differences == 1, "축 \(condition.axis)에서 \(differences)개가 달라졌다")
        }
    }

    @Test("기준값과 같은 조건은 중복으로 넣지 않는다")
    func 중복_제거() {
        let conditions = SweepPlan.conditions(
            baseline: baseline, exposures: ["1/1000"], distances: [6],
            trajectoryLengths: [5], maxRadii: [0.015]
        )
        #expect(conditions.count == 1, "전부 기준값과 같으므로 기준 하나만 남아야 한다")
    }

    /// 영상을 바꾸는 축과 분석만 바꾸는 축이 나뉜다.
    /// 분석 축은 같은 영상으로 돌아야 합성 시간이 절약된다.
    @Test("분석 파라미터는 영상 키를 바꾸지 않는다")
    func 영상_키() {
        let a = SweepPlan.Condition(
            exposure: "1/1000", distanceMeters: 6,
            trajectoryLength: 5, minRadius: 0.002, maxRadius: 0.015, axis: "기준"
        )
        let b = SweepPlan.Condition(
            exposure: "1/1000", distanceMeters: 6,
            trajectoryLength: 10, minRadius: 0.002, maxRadius: 0.030, axis: "궤적 길이"
        )
        #expect(a.videoKey == b.videoKey, "분석 파라미터만 다르면 같은 영상이다")

        let c = SweepPlan.Condition(
            exposure: "1/250", distanceMeters: 6,
            trajectoryLength: 5, minRadius: 0.002, maxRadius: 0.015, axis: "노출"
        )
        #expect(a.videoKey != c.videoKey, "노출이 다르면 다른 영상이다")
    }
}

// MARK: - 리포트

@Suite("스윕 리포트")
struct SweepReportTests {

    private func entry(_ recall: Double, _ precision: Double, axis: String = "축") -> SweepReport.Entry {
        // recall·precision을 만드는 정수 조합을 역산한다
        let tp = 100
        let fn = Int((Double(tp) / recall - Double(tp)).rounded())
        let fp = Int((Double(tp) / precision - Double(tp)).rounded())
        return .init(
            condition: .init(SweepPlan.Condition(
                exposure: "1/1000", distanceMeters: 6, trajectoryLength: 5,
                minRadius: 0.002, maxRadius: 0.015, axis: axis
            )),
            metrics: .init(truePositives: tp, falsePositives: fp, falseNegatives: fn),
            clipCount: 1
        )
    }

    /// 게이트 판정 기준이 recall이므로 recall로 고른다.
    @Test("recall이 가장 높은 조건을 고른다")
    func 최고_recall() {
        let report = SweepReport(mode: .synthetic, generatedAt: Date(), results: [
            entry(0.5, 1.0, axis: "낮은 recall"),
            entry(0.9, 0.5, axis: "높은 recall"),
            entry(0.7, 1.0, axis: "중간"),
        ])
        #expect(report.best?.condition.axis == "높은 recall")
    }

    /// 동률이면 헛검출이 적은 쪽이 낫다.
    @Test("recall 동률이면 precision으로 가른다")
    func 동률() {
        let report = SweepReport(mode: .synthetic, generatedAt: Date(), results: [
            entry(0.8, 0.4, axis: "헛검출 많음"),
            entry(0.8, 0.9, axis: "헛검출 적음"),
        ])
        #expect(report.best?.condition.axis == "헛검출 적음")
    }

    @Test("결과가 없으면 best도 없다")
    func 빈_결과() {
        let report = SweepReport(mode: .synthetic, generatedAt: Date(), results: [])
        #expect(report.best == nil)
    }
}

// MARK: - 인자

@Suite("sweep 인자")
struct SweepArgumentTests {

    @Test("목록을 해석한다")
    func 목록_해석() throws {
        let command = try Sweep.parse(["--out", "/tmp"])
        #expect(command.parseStrings("1/1000, 1/500 ,1/250") == ["1/1000", "1/500", "1/250"])
        #expect(command.parseDoubles("5,6,8") == [5, 6, 8])
        #expect(command.parseInts("5,7,10") == [5, 7, 10])
        #expect(command.parseStrings("") == [])
    }

    @Test("없는 클립 디렉터리는 거부")
    func 없는_클립() {
        #expect(throws: (any Error).self) {
            try Sweep.parse(["--out", "/tmp", "--clips", "/does/not/exist"])
        }
    }

    @Test("타구 수는 1 이상")
    func 타구_수() {
        #expect(throws: (any Error).self) {
            try Sweep.parse(["--out", "/tmp", "--hits=0"])
        }
    }
}
