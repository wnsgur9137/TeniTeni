import ArgumentParser
import Foundation
import TeniVision

/// 영상에 궤적 검출을 돌려 프로토콜 5.5 포맷 JSON을 낸다.
///
/// Phase 0 게이트 판정의 측정 도구다. 다만 **판정 자체는 #9**가 여러 조건을
/// 모아 내린다 — 이 도구는 클립 하나를 본다.
public struct Analyze: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "영상에서 공 궤적을 검출해 JSON으로 내보냅니다",
        discussion: """
            정답(teni synth의 .json 또는 라벨링 도구 출력)을 --ground-truth로 주면
            임팩트 매칭과 검출률까지 산출합니다.

            측정 정의는 docs/02-설계/CAPTURE-PROTOCOL.md 5.5절에 있습니다.

            예: teni analyze clip.mov --ground-truth clip.json --out result.json
            """
    )

    @Argument(help: "분석할 영상 경로")
    var video: String

    @Option(name: .shortAndLong, help: "출력 JSON 경로. 생략하면 영상과 같은 이름의 .result.json")
    var out: String?

    @Option(help: "정답 JSON. teni synth 출력 또는 라벨링 도구 출력")
    var groundTruth: String?

    @Option(help: "궤적 확정에 필요한 점 개수 (최소 5)")
    var trajectoryLength: Int = 5

    @Option(help: "검출 대상 최소 정규화 반지름")
    var minRadius: Double = 0.002

    @Option(help: "검출 대상 최대 정규화 반지름")
    var maxRadius: Double = 0.015

    @Option(help: "촬영 조건 — 장소")
    var location: String = "synthetic"

    @Option(help: "촬영 조건 — 조명")
    var light: String = "uniform"

    @Option(help: "촬영 조건 — 배경")
    var background: String = "simple"

    public init() {}

    public func validate() throws {
        guard trajectoryLength >= 5 else {
            throw ValidationError("trajectoryLength는 5 이상이어야 합니다 (Vision 요구사항)")
        }
        guard minRadius > 0, maxRadius > minRadius else {
            throw ValidationError("반지름 범위가 유효하지 않습니다")
        }
        guard FileManager.default.fileExists(atPath: video) else {
            throw ValidationError("영상을 찾을 수 없습니다: \(video)")
        }
        if let groundTruth, !FileManager.default.fileExists(atPath: groundTruth) {
            throw ValidationError("정답 파일을 찾을 수 없습니다: \(groundTruth)")
        }
    }

    // AsyncParsableCommand다. 세마포어로 async를 건너면 Swift 6의
    // sending 검사에 걸리고, 무엇보다 그럴 이유가 없다.
    public func run() async throws {
        try await execute(loadContext())
    }

    // MARK: 실행

    private struct Context {
        let videoURL: URL
        let outputURL: URL
        let truth: TruthEnvelope?
    }

    /// `teni synth`의 `GroundTruth`와 `teni label`의 `LabelSet`을 **둘 다** 받는다.
    /// 정답이 합성에서 왔는지 사람에게서 왔는지는 분석에 상관없다 —
    /// 필요한 것은 임팩트 프레임과 촬영 메타뿐이다.
    struct TruthEnvelope: Decodable {
        struct Truth: Decodable {
            let impactFrames: [Int]
        }
        let groundTruth: Truth
        let capture: GroundTruth.Capture?
    }

    private func loadContext() throws -> Context {
        let videoURL = URL(fileURLWithPath: video)
        let outputURL = out.map { URL(fileURLWithPath: $0) }
            ?? videoURL.deletingPathExtension().appendingPathExtension("result.json")

        var truth: TruthEnvelope?
        if let groundTruth {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            truth = try decoder.decode(
                TruthEnvelope.self,
                from: Data(contentsOf: URL(fileURLWithPath: groundTruth))
            )
        }
        return Context(videoURL: videoURL, outputURL: outputURL, truth: truth)
    }

    private func execute(_ context: Context) async throws {
        let analyzer = TrajectoryAnalyzer(
            trajectoryLength: trajectoryLength,
            minimumRadius: Float(minRadius),
            maximumRadius: Float(maxRadius)
        )
        let output = try await analyzer.analyze(url: context.videoURL)

        let impactFrames = context.truth?.groundTruth.impactFrames
        let candidates = output.trajectories.map {
            ImpactMatcher.Candidate(startFrame: $0.startFrame, durationSec: $0.durationSec)
        }
        let outcome = impactFrames.map {
            ImpactMatcher.match(candidates: candidates, impactFrames: $0)
        }

        let report = makeReport(context: context, output: output, outcome: outcome,
                                impactFrames: impactFrames)
        try report.write(to: context.outputURL)
        printSummary(context: context, output: output, report: report)
    }

    private func makeReport(
        context: Context,
        output: TrajectoryAnalyzer.Output,
        outcome: ImpactMatcher.Outcome?,
        impactFrames: [Int]?
    ) -> DetectionReport {
        let capture = context.truth?.capture
        let pixelsPerRadius = Double(output.video.width)

        let detections = output.trajectories.enumerated().map { index, trajectory in
            DetectionReport.Detection(
                startFrame: trajectory.startFrame,
                durationSec: trajectory.durationSec,
                matchedImpact: outcome?.matches[index] ?? nil,
                movingAverageRadius: trajectory.movingAverageRadius,
                // 정규화 반지름 → 픽셀. 가로 해상도가 기준이다 (정사각 영상으로 확인).
                // 이 값은 공 크기가 아니라 블러를 포함한 바운딩 원이다.
                detectedDiameterPx: trajectory.movingAverageRadius * 2 * pixelsPerRadius,
                pointCount: trajectory.pointCount,
                confidence: trajectory.confidence
            )
        }

        var result: DetectionReport.Result?
        if let outcome, let impactFrames {
            result = .init(
                hits: outcome.hits,
                total: impactFrames.count,
                detectionRate: ImpactMatcher.detectionRate(
                    hits: outcome.hits, impactCount: impactFrames.count
                ),
                falsePositives: outcome.falsePositives
            )
        }

        return DetectionReport(
            clipId: context.videoURL.deletingPathExtension().lastPathComponent,
            condition: .init(location: location, light: light, background: background),
            capture: .init(
                fps: capture?.fps ?? output.video.fps,
                resolution: "\(output.video.width)x\(output.video.height)",
                exposureDuration: capture?.exposureDuration ?? "unknown",
                distanceM: capture?.distanceM ?? 0,
                heightM: capture?.heightM ?? 0
            ),
            params: .init(
                trajectoryLength: trajectoryLength,
                minRadius: minRadius,
                maxRadius: maxRadius
            ),
            groundTruth: impactFrames.map { .init(impactFrames: $0) },
            detected: detections,
            result: result
        )
    }

    private func printSummary(
        context: Context,
        output: TrajectoryAnalyzer.Output,
        report: DetectionReport
    ) {
        print("""
            분석 완료
              영상      \(context.videoURL.lastPathComponent)
              프레임    \(output.video.frameCount) (\(String(format: "%.0f", output.video.fps))fps, \(output.video.width)x\(output.video.height))
              파라미터  trajectoryLength=\(trajectoryLength) radius=\(minRadius)~\(maxRadius)
              검출 궤적 \(report.detected.count)개
              결과      \(context.outputURL.path)
            """)

        if !output.timeRangeAvailable && !report.detected.isEmpty {
            print("  ⚠️ timeRange를 얻지 못해 startFrame이 근사값입니다")
        }

        if let result = report.result {
            print("""
                  ─────
                  타구      \(result.total)개
                  매칭      \(result.hits)개
                  검출률    \(String(format: "%.1f%%", result.detectionRate * 100))
                  오검출    \(result.falsePositives)개
                """)
        } else {
            print("  (정답이 없어 검출 목록만 냈습니다 — --ground-truth로 매칭할 수 있습니다)")
        }

        if report.detected.isEmpty {
            print("""

                검출 0건입니다. 게이트가 재려는 값이 이것일 수도 있지만,
                합성 영상은 실영상보다 쉬우므로 먼저 확인할 것:
                  · --min-radius / --max-radius 범위가 공 크기를 담는가
                  · 영상이 정말 공이 움직이는 구간을 담고 있는가
                """)
        }
    }
}
