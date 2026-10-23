import AVFoundation
import Foundation
import Testing
@testable import TeniVision

private let fps = 30.0

/// 프레임을 순서대로 먹이고, 지정한 인덱스에서 후보를 넣는다.
private func run(
    _ recorder: ClipRecorder<TestFrame>,
    frames: [TestFrame],
    candidates: [Int: SwingCandidate],
    finish: Bool = true
) async throws -> [RecordedClip] {
    var clips: [RecordedClip] = []
    for (index, frame) in frames.enumerated() {
        if let clip = try await recorder.enqueue(frame) { clips.append(clip) }
        if let candidate = candidates[index],
           let clip = try await recorder.accept(candidate) {
            clips.append(clip)
        }
    }
    if finish, let clip = try await recorder.finish() { clips.append(clip) }
    return clips
}

@Suite("스윙 클립 기록")
struct ClipRecorderTests {

    @Test("후보 하나가 클립 하나가 된다")
    func 단일_클립() async throws {
        let directory = ClipFixture.directory()
        let recorder = ClipRecorder<TestFrame>(directory: directory, stamp: "s")
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 6, fps: fps),
            candidates: [90: ClipFixture.candidate(triggeredAt: 3.0)]
        )

        #expect(clips.count == 1)
        let clip = try #require(clips.first)
        // 1.0초부터 5.0초까지 30fps = 121장
        #expect(clip.frameCount == 121)
        #expect(clip.startedAt == 1.0)
        #expect(abs(clip.duration - 4.0) < 0.001)
        #expect(clip.url.lastPathComponent == "s-1.mov")
        // 파일을 다시 열어 센다. 보고한 수와 실제 파일이 어긋나면
        // 도메인에는 있는데 재생할 수 없는 클립이 된다.
        #expect(try await sampleCount(of: clip.url) == 121)
    }

    @Test("스윙 시각은 클립 시작 기준 상대초다")
    func 상대초() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 6, fps: fps),
            candidates: [90: ClipFixture.candidate(triggeredAt: 3.0)]
        )

        let swing = try #require(clips.first?.swings.first)
        // 절대 시각은 1.0 / 3.0 / 5.0 이고 클립은 1.0에서 시작한다
        #expect(swing.startSeconds == 0.0)
        #expect(abs(swing.impactSeconds - 2.0) < 0.001)
        #expect(abs(swing.endSeconds - 4.0) < 0.001)
    }

    @Test("겹치는 후보 둘은 클립 하나에 스윙 둘로 들어간다")
    func 병합_클립() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 7, fps: fps),
            candidates: [
                90: ClipFixture.candidate(triggeredAt: 3.0),
                120: ClipFixture.candidate(triggeredAt: 4.0),
            ]
        )

        #expect(clips.count == 1)
        let clip = try #require(clips.first)
        // 수를 먼저 단정해 통과시키지 않으면 아래 인덱스 접근이 런너를
        // 죽인다 — 실패가 "크래시"로 보이면 원인이 가려진다
        try #require(clip.swings.count == 2)
        // 1.0초부터 6.0초까지 = 151장. 병합으로 구간이 버퍼 창(3초)보다
        // 길어졌는데도 머리가 잘리지 않는다 — 스트리밍이라 그렇다
        #expect(clip.frameCount == 151)
        #expect(abs(clip.swings[0].impactSeconds - 2.0) < 0.001)
        #expect(abs(clip.swings[1].impactSeconds - 3.0) < 0.001)
        #expect(abs(clip.swings[1].startSeconds - 1.0) < 0.001)
    }

    @Test("떨어진 후보 둘은 클립 둘이 된다")
    func 분리_클립() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 13, fps: fps),
            candidates: [
                90: ClipFixture.candidate(triggeredAt: 3.0),
                300: ClipFixture.candidate(triggeredAt: 10.0),
            ]
        )

        #expect(clips.count == 2)
        #expect(clips.map(\.frameCount) == [121, 121])
        #expect(clips.map(\.url.lastPathComponent) == ["s-1.mov", "s-2.mov"])
        #expect(clips.allSatisfy { $0.swings.count == 1 })
    }

    @Test("세션 시작 직후면 가진 프레임만 쓴다")
    func 하한이_음수() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 3.5, fps: fps),
            // 구간이 -1.5...2.5 다 — 하한이 버퍼 밖이다
            candidates: [15: ClipFixture.candidate(triggeredAt: 0.5)]
        )

        let clip = try #require(clips.first)
        // 0.0초부터 2.5초까지 = 76장
        #expect(clip.frameCount == 76)
        #expect(clip.startedAt == 0.0)
        // 음수 하한은 0으로 눌린다
        #expect(clip.swings.first?.startSeconds == 0.0)
        #expect(abs((clip.swings.first?.impactSeconds ?? -1) - 0.5) < 0.001)
    }

    @Test("프레임이 하나도 없으면 클립을 만들지 않는다")
    func 빈_클립_없음() async throws {
        let directory = ClipFixture.directory()
        let recorder = ClipRecorder<TestFrame>(directory: directory, stamp: "s")
        #expect(try await recorder.accept(ClipFixture.candidate(triggeredAt: 3.0)) == nil)
        #expect(try await recorder.finish() == nil)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.isEmpty)
    }

    @Test("종료 시 postRoll을 못 채운 구간도 쓴다")
    func 미완_구간() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            // 5.0초까지 가지 못하고 4.0초에서 끝난다
            frames: ClipFixture.frames(from: 0, to: 4, fps: fps),
            candidates: [90: ClipFixture.candidate(triggeredAt: 3.0)]
        )

        let clip = try #require(clips.first)
        #expect(clips.count == 1)
        // 1.0초부터 4.0초까지 = 91장
        #expect(clip.frameCount == 91)
        #expect(FileManager.default.fileExists(atPath: clip.url.path))
    }

    @Test("후보가 없으면 아무것도 쓰지 않는다")
    func 후보_없음() async throws {
        let directory = ClipFixture.directory()
        let recorder = ClipRecorder<TestFrame>(directory: directory, stamp: "s")
        let clips = try await run(
            recorder, frames: ClipFixture.frames(from: 0, to: 3, fps: fps), candidates: [:]
        )

        #expect(clips.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("버퍼는 preRoll과 여유만큼만 들고 있는다")
    func 버퍼_창() async throws {
        let recorder = ClipRecorder<TestFrame>(
            profile: .default, margin: 1.0, directory: ClipFixture.directory(), stamp: "s"
        )
        for frame in ClipFixture.frames(from: 0, to: 10, fps: fps) {
            _ = try await recorder.enqueue(frame)
        }
        // 창 3초 = 90프레임 간격. 경계 하나는 밀려날 수 있다
        let count = await recorder.bufferedFrameCount
        #expect(count <= 91)
        #expect(count >= 89)
    }
}
