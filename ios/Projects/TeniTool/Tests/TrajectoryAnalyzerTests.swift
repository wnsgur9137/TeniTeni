import AVFoundation
import Foundation
import Testing
@testable import TeniToolKit

/// `TrajectoryAnalyzer.analyze`는 게이트 판정의 핵심 경로다.
/// [SPEC-0007](docs/07-기획/SPEC-0007-analyze-cli.md)이 지켜야 한다고 정한
/// 세 가지가 전부 여기에 걸려 있는데, 지금까지 **CLI로 손수 실행해 확인했을
/// 뿐 자동 검증이 없었다** (이슈 #35).
///
/// - `StatefulRequest` 인스턴스 재사용 — 프레임마다 새로 만들면 궤적이 확정되지 않는다
/// - `CMSampleBuffer` 공급 — `CGImage`로 바꾸면 `timeRange`가 nil이 된다
/// - `uuid` 중복 제거 — 없으면 한 타구를 여러 번 센다

/// 합성 클립을 테스트 간 공유한다.
///
/// 테스트마다 영상을 새로 만들면 게이트가 9분을 넘는다 — 합성과 분석이
/// 모두 프레임 수에 비례하기 때문이다. 같은 조건이면 한 번만 만든다.
actor ClipCache {
    static let shared = ClipCache()

    private var clips: [String: (movie: URL, truth: GroundTruth)] = [:]
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "teni-test-clips-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// 정답을 아는 합성 영상. `teni synth`와 같은 경로를 쓴다.
    func clip(
        exposure: String = "1/1000", hits: Int = 3, height: Int = 512
    ) throws -> (movie: URL, truth: GroundTruth) {
        let key = "\(exposure)-\(hits)-\(height)".replacingOccurrences(of: "/", with: "_")
        if let cached = clips[key] { return cached }

        let movie = directory.appending(path: "\(key).mov")
        let command = try Synth.parse([
            "--out", movie.path, "--exposure", exposure, "--fps", "120",
            "--hits", "\(hits)", "--hit-interval", "1.5",
            "--height", "\(height)", "--noise", "0",
        ])
        let plan = try SynthPlan(command: command)
        let session = try VideoWriter(
            url: movie, width: plan.camera.widthPx, height: plan.camera.heightPx, fps: plan.fps
        ).makeSession()
        let truth = try plan.render { _, frame in try session.append(frame) }
        try session.finish()

        let entry = (movie: movie, truth: truth)
        clips[key] = entry
        return entry
    }

    /// 임시 파일을 쓸 디렉터리
    func scratch() -> URL { directory }
}

@Suite("궤적 분석 end-to-end")
struct TrajectoryAnalyzerTests {

    private var analyzer: TrajectoryAnalyzer {
        TrajectoryAnalyzer(trajectoryLength: 5, minimumRadius: 0.002, maximumRadius: 0.030)
    }

    // MARK: 핵심 경로

    /// 검출이 일어나고 타구마다 궤적이 하나씩 나온다.
    /// **`uuid` 중복 제거가 깨지면 개수가 늘어난다.**
    @Test("타구 수만큼 궤적이 검출된다")
    func 검출() async throws {
        let clip = try await ClipCache.shared.clip(hits: 3)
        let output = try await analyzer.analyze(url: clip.movie)

        #expect(output.trajectories.count == 3, "타구 3개 → 궤적 3개")
        #expect(output.video.fps == 120)
        #expect(output.video.width == 1920)
    }

    /// **`CMSampleBuffer`로 먹여야 `timeRange`가 나온다.**
    /// `CGImage` 경로로 바꾸면 이 값이 false가 되고 `startFrame`이
    /// 프레임 카운터 기반 근사로 떨어진다.
    @Test("timeRange를 얻는다")
    func timeRange() async throws {
        let clip = try await ClipCache.shared.clip(hits: 1)
        let output = try await analyzer.analyze(url: clip.movie)

        #expect(
            output.timeRangeAvailable,
            "timeRange가 없으면 startFrame이 근사값이 되어 임팩트 매칭이 어긋난다"
        )
    }

    /// `timeRange`가 **궤적 시작 시점**을 담는지 본다.
    /// 정답 임팩트와 차이가 크면 매칭 허용오차(±3)를 넘어 검출률이 0이 된다.
    @Test("startFrame이 정답 임팩트와 일치한다")
    func 시작_프레임() async throws {
        let clip = try await ClipCache.shared.clip(hits: 3)
        let output = try await analyzer.analyze(url: clip.movie)
        let impacts = clip.truth.groundTruth.impactFrames

        #expect(output.trajectories.count == impacts.count)
        for (trajectory, impact) in zip(
            output.trajectories.sorted(by: { $0.startFrame < $1.startFrame }),
            impacts.sorted()
        ) {
            let difference = abs(trajectory.startFrame - impact)
            #expect(
                difference <= ImpactMatcher.frameTolerance,
                "궤적 \(trajectory.startFrame) vs 임팩트 \(impact) — 차이 \(difference)"
            )
        }
    }

    /// **`StatefulRequest` 인스턴스를 재사용해야 한다.**
    /// 프레임마다 새로 만들면 상태가 누적되지 않아 `trajectoryLength`(5)를
    /// 절대 채우지 못하고 검출이 0이 된다. 검출점이 5개 이상 모였다는 것이
    /// 상태가 이어졌다는 증거다.
    @Test("검출점이 trajectoryLength 이상 모인다")
    func 상태_누적() async throws {
        let clip = try await ClipCache.shared.clip(hits: 1)
        let output = try await analyzer.analyze(url: clip.movie)

        let trajectory = try #require(output.trajectories.first)
        #expect(
            trajectory.pointCount >= 5,
            "요청 인스턴스를 재사용하지 않으면 점이 모이지 않는다"
        )
        #expect(trajectory.durationSec >= ImpactMatcher.minimumDurationSeconds)
    }

    /// 전 구간을 통과해 `uuid`가 유지되는지 본다.
    @Test("궤적마다 uuid가 다르다")
    func uuid_고유성() async throws {
        let clip = try await ClipCache.shared.clip(hits: 3)
        let output = try await analyzer.analyze(url: clip.movie)

        let uuids = Set(output.trajectories.map(\.uuid))
        #expect(uuids.count == output.trajectories.count, "uuid가 겹치면 중복 제거가 깨진다")
    }

    // MARK: 파라미터

    /// 반지름 범위를 공보다 작게 잡으면 검출이 사라져야 한다.
    /// 파라미터가 실제로 요청에 전달되는지 확인하는 방법이다.
    @Test("반지름 범위 밖이면 검출되지 않는다")
    func 반지름_범위() async throws {
        let clip = try await ClipCache.shared.clip(hits: 1)
        let tooSmall = TrajectoryAnalyzer(
            trajectoryLength: 5, minimumRadius: 0.0001, maximumRadius: 0.0005
        )
        let output = try await tooSmall.analyze(url: clip.movie)
        #expect(output.trajectories.isEmpty, "공보다 작은 범위로는 잡히면 안 된다")
    }

    // MARK: 실패 경로

    @Test("없는 파일은 던진다")
    func 없는_파일() async {
        let missing = URL(fileURLWithPath: "/does/not/exist.mov")
        await #expect(throws: (any Error).self) {
            try await analyzer.analyze(url: missing)
        }
    }

    @Test("영상이 아닌 파일은 던진다")
    func 잘못된_파일() async throws {
        let fake = await ClipCache.shared.scratch().appending(path: "fake-analyze.mov")
        try Data("not a movie".utf8).write(to: fake)
        await #expect(throws: (any Error).self) {
            try await analyzer.analyze(url: fake)
        }
    }
}
