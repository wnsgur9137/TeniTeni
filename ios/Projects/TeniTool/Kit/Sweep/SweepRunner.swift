import Foundation
import TeniVision

/// 조건별로 영상을 준비하고 분석해 지표를 모은다.
public struct SweepRunner: Sendable {

    public let outputDirectory: URL
    public let hits: Int
    public let fps: Double
    public let height: Int
    public let noise: Double
    /// 주어지면 실영상 모드. 합성하지 않고 이 디렉터리의 클립을 쓴다.
    public let clipsDirectory: URL?

    public init(
        outputDirectory: URL, hits: Int, fps: Double, height: Int, noise: Double,
        clipsDirectory: URL?
    ) {
        self.outputDirectory = outputDirectory
        self.hits = hits
        self.fps = fps
        self.height = height
        self.noise = noise
        self.clipsDirectory = clipsDirectory
    }

    public func run(conditions: [SweepPlan.Condition]) async throws -> [SweepReport.Entry] {
        var entries: [SweepReport.Entry] = []
        // 영상을 바꾸는 축만 캐시한다. 분석 파라미터는 같은 영상으로 돈다.
        var videoCache: [String: (video: URL, truth: URL)] = [:]

        for (index, condition) in conditions.enumerated() {
            let label = "[\(index + 1)/\(conditions.count)] \(condition.axis)"

            // 조건 하나가 실패해도 나머지를 돈다. 스윕은 15분이 넘는 작업이라
            // 불가능한 조합 하나 때문에 전부 날리면 안 된다 — 실제로 1/60s를
            // 120fps에 넣었다가 914초짜리 실행을 잃었다 (이슈 #32).
            do {
                let entry = try await runCondition(
                    condition, label: label, videoCache: &videoCache
                )
                entries.append(entry)
            } catch {
                print("\(label) ⚠️ 건너뜀 — \(error)")
            }
        }
        return entries
    }

    private func runCondition(
        _ condition: SweepPlan.Condition,
        label: String,
        videoCache: inout [String: (video: URL, truth: URL)]
    ) async throws -> SweepReport.Entry {
        let sources: [(video: URL, truth: URL)]

        do {
            if let clipsDirectory {
                sources = try realClips(in: clipsDirectory)
                guard !sources.isEmpty else {
                    throw Failure.noClips(clipsDirectory.path)
                }
            } else {
                let key = condition.videoKey
                if videoCache[key] == nil {
                    print("\(label) 합성 중 — \(key)")
                    videoCache[key] = try await synthesize(condition, key: key)
                }
                sources = [videoCache[key]!]
            }
        }

        var total = DetectionMetrics(truePositives: 0, falsePositives: 0, falseNegatives: 0)
        for source in sources {
            let metrics = try await analyze(condition, video: source.video, truth: source.truth)
            total = DetectionMetrics(
                truePositives: total.truePositives + metrics.truePositives,
                falsePositives: total.falsePositives + metrics.falsePositives,
                falseNegatives: total.falseNegatives + metrics.falseNegatives
            )
        }

        print("""
            \(label) recall \(String(format: "%.1f%%", total.recall * 100)) \
            precision \(String(format: "%.1f%%", total.precision * 100))
            """)

        // 검출이 0이면 검출기 문제인지 영상 문제인지 구분할 수 없다.
        // 공이 화면에 얼마나 있었는지 보여주고 사람이 판단하게 한다.
        if total.truePositives == 0, clipsDirectory == nil,
           let truth = try? loadTruth(sources[0].truth) {
            let counts = Self.visibleFrameCounts(
                truth, width: truth.capture.widthPx, height: truth.capture.heightPx
            )
            let summary = counts.sorted { $0.key < $1.key }
                .map { "타구\($0.key + 1) \($0.value)프레임" }
                .joined(separator: " · ")
            print("      검출 0 — 공이 화면 안에 있던 프레임: \(summary)")
            print("      (검출에 최소 \(condition.trajectoryLength)프레임이 필요합니다)")
        }

        return .init(condition: .init(condition), metrics: total, clipCount: sources.count)
    }

    // MARK: 합성

    private func synthesize(
        _ condition: SweepPlan.Condition, key: String
    ) async throws -> (video: URL, truth: URL) {
        let movie = outputDirectory.appending(path: "synth-\(key).mov")
        let truth = movie.deletingPathExtension().appendingPathExtension("json")

        // 이미 있으면 재사용한다 — 1/60s는 하위 표본이 106장이라 생성이 느리다
        if FileManager.default.fileExists(atPath: movie.path),
           FileManager.default.fileExists(atPath: truth.path) {
            return (movie, truth)
        }

        let command = try Synth.parse([
            "--out", movie.path,
            "--exposure", condition.exposure,
            "--distance", "\(condition.distanceMeters)",
            "--fps", "\(fps)",
            "--height", "\(height)",
            "--hits", "\(hits)",
            "--noise", "\(noise)",
        ])
        let plan = try SynthPlan(command: command)

        // 스트리밍으로 쓴다. 배열로 쌓으면 1080p 9조건에서 메모리가 터진다
        // (이슈 #31).
        let session = try VideoWriter(
            url: movie, width: plan.camera.widthPx, height: plan.camera.heightPx, fps: plan.fps
        ).makeSession()
        let groundTruth = try plan.render { _, frame in try session.append(frame) }
        try session.finish()
        try groundTruth.write(to: truth)

        return (movie, truth)
    }

    /// 타구별로 공이 화면 안에 있는 프레임 수를 센다.
    ///
    /// **경고로 쓰지 않는다.** 처음에는 이탈 비율 30% 초과를 경고로 삼았는데
    /// 오탐이었다 — 공이 프레임을 가로지르는 것은 정상이고, 1080p·6m에서
    /// 이탈이 77%인데 검출은 100%였다. 기준을 "화면 안 프레임 ≥
    /// trajectoryLength"로 바꿨더니 이번엔 놓쳤다. 360p에서 공이 위로
    /// 벗어나 검출이 0인데 22프레임이 남아 경고가 안 떴다.
    ///
    /// 프레이밍이 충분한지 기계적으로 판단할 방법을 찾지 못했다. 대신
    /// **검출이 0일 때 이 숫자를 보여주고 사람이 판단하게 한다.**
    static func visibleFrameCounts(
        _ truth: GroundTruth, width: Int, height: Int
    ) -> [Int: Int] {
        let radius = truth.synthetic.ballDiameterPx / 2
        var counts: [Int: Int] = [:]
        for center in truth.groundTruth.ballCenters {
            let visible = center.x + radius >= 0 && center.x - radius <= Double(width)
                && center.y + radius >= 0 && center.y - radius <= Double(height)
            counts[center.hitIndex, default: 0] += visible ? 1 : 0
        }
        return counts
    }

    // MARK: 분석

    private func analyze(
        _ condition: SweepPlan.Condition, video: URL, truth: URL
    ) async throws -> DetectionMetrics {
        let analyzer = TrajectoryAnalyzer(
            trajectoryLength: condition.trajectoryLength,
            minimumRadius: Float(condition.minRadius),
            maximumRadius: Float(condition.maxRadius)
        )
        let output = try await analyzer.analyze(url: video)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            Analyze.TruthEnvelope.self, from: Data(contentsOf: truth)
        )
        let impacts = envelope.groundTruth.impactFrames

        let candidates = output.trajectories.map {
            ImpactMatcher.Candidate(startFrame: $0.startFrame, durationSec: $0.durationSec)
        }
        let outcome = ImpactMatcher.match(candidates: candidates, impactFrames: impacts)

        return DetectionMetrics(
            truePositives: outcome.hits,
            falsePositives: outcome.falsePositives,
            falseNegatives: impacts.count - outcome.hits
        )
    }

    private func loadTruth(_ url: URL) throws -> GroundTruth {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GroundTruth.self, from: Data(contentsOf: url))
    }

    // MARK: 실영상

    /// 영상과 같은 이름의 `.truth.json` 또는 `.json`을 정답으로 본다.
    private func realClips(in directory: URL) throws -> [(video: URL, truth: URL)] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { video in
                let base = video.deletingPathExtension()
                for candidate in [
                    base.appendingPathExtension("truth.json"),
                    base.appendingPathExtension("json"),
                ] where FileManager.default.fileExists(atPath: candidate.path) {
                    return (video, candidate)
                }
                return nil
            }
    }

    enum Failure: Error, CustomStringConvertible {
        case noClips(String)

        var description: String {
            switch self {
            case .noClips(let path):
                "\(path)에 정답(.truth.json 또는 .json)이 딸린 영상이 없습니다"
            }
        }
    }
}
