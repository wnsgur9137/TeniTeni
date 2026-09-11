import ArgumentParser
import Foundation
import TeniVision

/// 조건을 바꿔가며 검출률을 집계하고 프로토콜 5.5 기준으로 판정한다.
///
/// **이 도구가 Phase 0 게이트를 판정하지 못한다** — 실영상이 필요하다.
/// 합성 모드는 도구가 동작함을 보이는 것이고, 거기서 나온 숫자는 게이트
/// 값이 아니다. 근거: docs/07-기획/SPEC-0009-parameter-sweep.md
public struct Sweep: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "파라미터를 바꿔가며 검출률을 집계하고 게이트를 판정합니다",
        discussion: """
            두 가지 모드가 있습니다.

              합성 모드 (기본)
                조건마다 영상을 만들어 분석합니다. 도구 검증용이며
                결과는 게이트 값이 아닙니다.

                  teni sweep --out sweep/

              실영상 모드
                이미 찍은 클립과 라벨로 파라미터만 스윕합니다.
                게이트 판정은 이 모드로 합니다.

                  teni sweep --clips 0b-clips/ --out sweep/

            축별 1차원 스윕입니다 — 기준값에서 한 축씩 움직입니다.
            측정 정의는 docs/02-설계/CAPTURE-PROTOCOL.md 5.5절에 있습니다.
            """
    )

    @Option(name: .shortAndLong, help: "결과를 쓸 디렉터리")
    var out: String

    @Option(help: "실영상 클립 디렉터리. 주면 실영상 모드로 돕니다")
    var clips: String?

    // MARK: 스윕 축

    @Option(help: "노출 축. 쉼표로 구분")
    var exposures: String = "1/1000,1/500,1/250"

    @Option(help: "거리 축 (m). 쉼표로 구분")
    var distances: String = "5,6,8"

    @Option(help: "궤적 길이 축. 쉼표로 구분")
    var trajectoryLengths: String = "5,7,10"

    @Option(help: "최대 반지름 축. 쉼표로 구분")
    var maxRadii: String = "0.008,0.015,0.030"

    // MARK: 합성 조건

    @Option(help: "합성 영상의 타구 수")
    var hits: Int = 5

    @Option(help: "합성 영상 fps")
    var fps: Double = 120

    @Option(help: "합성 영상 세로 해상도. 줄이면 빨라집니다")
    var height: Int = 1080

    @Option(help: "합성 영상 노이즈")
    var noise: Double = 0.01

    public init() {}

    public func validate() throws {
        guard hits > 0 else { throw ValidationError("타구 수는 1 이상이어야 합니다") }
        guard fps > 0, height > 0 else { throw ValidationError("fps·해상도가 유효하지 않습니다") }
        if let clips, !FileManager.default.fileExists(atPath: clips) {
            throw ValidationError("클립 디렉터리를 찾을 수 없습니다: \(clips)")
        }
    }

    public func run() async throws {
        let outputDirectory = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )

        let conditions = SweepPlan.conditions(
            baseline: .init(),
            exposures: parseStrings(exposures),
            distances: parseDoubles(distances),
            trajectoryLengths: parseInts(trajectoryLengths),
            maxRadii: parseDoubles(maxRadii)
        )

        printHeader(conditions: conditions)

        let runner = SweepRunner(
            outputDirectory: outputDirectory,
            hits: hits, fps: fps, height: height, noise: noise,
            clipsDirectory: clips.map { URL(fileURLWithPath: $0) }
        )
        let results = try await runner.run(conditions: conditions)

        let report = SweepReport(
            mode: clips == nil ? .synthetic : .realFootage,
            generatedAt: Date(),
            results: results
        )
        try report.write(to: outputDirectory.appending(path: "sweep.json"))

        printTable(report)
        printVerdict(report)
    }

    // MARK: 출력

    private func printHeader(conditions: [SweepPlan.Condition]) {
        print("""
            스윕 시작
              모드      \(clips == nil ? "합성 (도구 검증용)" : "실영상 (게이트 판정)")
              조건      \(conditions.count)개
              출력      \(out)
            """)
        if clips == nil {
            print("""

                ⚠️ 합성 모드입니다. 배경이 균일하고 공만 움직이므로 실영상보다
                   쉽습니다. 여기서 나온 숫자는 게이트 값이 아닙니다.
                """)
        }
        print("")
    }

    private func printTable(_ report: SweepReport) {
        print("\n결과")
        print("  \(pad("축", 10)) \(pad("노출", 8)) \(pad("거리", 5)) \(pad("길이", 5)) \(pad("최대R", 7)) \(pad("recall", 8)) \(pad("prec", 7)) \(pad("F1", 7)) 판정")
        print("  " + String(repeating: "─", count: 78))

        var lastAxis = ""
        for result in report.results {
            if result.condition.axis != lastAxis {
                if !lastAxis.isEmpty { print("") }
                lastAxis = result.condition.axis
            }
            let m = result.metrics
            let warning = m.precisionIsLow ? " ⚠️헛검출" : ""
            print("""
                  \(pad(result.condition.axis, 10)) \(pad(result.condition.exposure, 8)) \
                \(pad("\(Int(result.condition.distanceM))m", 5)) \
                \(pad("\(result.condition.trajectoryLength)", 5)) \
                \(pad(String(format: "%.3f", result.condition.maxRadius), 7)) \
                \(pad(percent(m.recall), 8)) \(pad(percent(m.precision), 7)) \
                \(pad(percent(m.f1), 7)) \(m.verdict.label)\(warning)
                """)
        }
    }

    private func printVerdict(_ report: SweepReport) {
        guard let best = report.best else {
            print("\n결과가 없습니다.")
            return
        }
        let m = best.metrics
        print("""

            ─────────────────────────────────────────
            최고 recall 조건
              노출 \(best.condition.exposure) · 거리 \(Int(best.condition.distanceM))m · \
            길이 \(best.condition.trajectoryLength) · 최대R \(String(format: "%.3f", best.condition.maxRadius))

              recall     \(percent(m.recall))   ← 게이트 판정 기준
              precision  \(percent(m.precision))
              F1         \(percent(m.f1))

              판정  \(m.verdict.label) — \(m.verdict.action)
            """)

        if m.precisionIsLow {
            print("""

                ⚠️ precision이 \(percent(m.precision))입니다. recall이 기준을 넘어도
                   타구 하나에 헛검출이 여럿 붙는다는 뜻이라 실사용이 어렵습니다.

                   게이트 기준에는 precision이 없습니다 (프로토콜 5.5).
                   이 도구는 드러내기만 하고 기준을 바꾸지 않습니다.
                """)
        }

        if report.mode == .synthetic {
            print("""

                ⚠️ 합성 영상 결과입니다. **Phase 0 게이트 판정이 아닙니다.**
                   판정하려면 0-B 실영상과 #8 라벨링이 필요합니다.

                     teni sweep --clips <실영상 디렉터리> --out <결과>
                """)
        }
    }

    // MARK: 보조

    func parseStrings(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func parseDoubles(_ text: String) -> [Double] {
        parseStrings(text).compactMap(Double.init)
    }

    func parseInts(_ text: String) -> [Int] {
        parseStrings(text).compactMap(Int.init)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
