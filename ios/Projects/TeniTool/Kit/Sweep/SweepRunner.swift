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
            let sources: [(video: URL, truth: URL)]

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
            entries.append(.init(condition: .init(condition), metrics: total, clipCount: sources.count))
        }
        return entries
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
        let output = plan.render()
        try VideoWriter(
            url: movie, width: plan.camera.widthPx, height: plan.camera.heightPx, fps: plan.fps
        ).write(frames: output.frames)
        try output.groundTruth.write(to: truth)

        // 공이 프레임을 벗어나면 검출이 0이 나오는데, 그것은 검출기 문제가
        // 아니라 영상 문제다. 해상도를 줄여 회전을 빠르게 하려다 실제로
        // 겪었다 — 세로를 360으로 줄이자 공이 위로 벗어나 전 조건이 0%였다.
        if let warning = Self.framingWarning(output.groundTruth, width: plan.camera.widthPx, height: plan.camera.heightPx) {
            print("      ⚠️ \(warning)")
        }
        return (movie, truth)
    }

    /// 정답 좌표가 화면 밖으로 나간 비율을 본다.
    static func framingWarning(_ truth: GroundTruth, width: Int, height: Int) -> String? {
        let centers = truth.groundTruth.ballCenters
        guard !centers.isEmpty else { return "정답에 공 좌표가 없습니다" }

        let radius = truth.synthetic.ballDiameterPx / 2
        let outside = centers.filter {
            $0.x + radius < 0 || $0.x - radius > Double(width)
                || $0.y + radius < 0 || $0.y - radius > Double(height)
        }
        let ratio = Double(outside.count) / Double(centers.count)
        guard ratio > 0.3 else { return nil }
        return String(
            format: "공이 프레임을 벗어난 비율 %.0f%% — 검출 0은 영상 문제일 수 있습니다. 해상도를 키우세요",
            ratio * 100
        )
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
