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
        // 스윙의 끝(절대 5.0초)은 클립에 없다. 상한으로 눌려야 한다 —
        // 누르지 않으면 클립 길이를 넘는 시각이 도메인에 들어간다
        let swing = try #require(clip.swings.first)
        #expect(abs(swing.endSeconds - clip.duration) < 0.001)
        #expect(swing.endSeconds <= clip.duration)
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

    @Test("후보 뒤에 프레임이 없어도 종료에서 쓴다")
    func 후보_직후_종료() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        let clips = try await run(
            recorder,
            // 마지막 프레임에서 후보가 들어온다 — 그 뒤로 아무것도 없다
            frames: ClipFixture.frames(from: 0, to: 3, fps: fps),
            candidates: [90: ClipFixture.candidate(triggeredAt: 3.0)]
        )

        let clip = try #require(clips.first)
        // 1.0초부터 3.0초까지 = 61장
        #expect(clip.frameCount == 61)
        #expect(try await sampleCount(of: clip.url) == 61)
    }

    @Test("종료를 두 번 불러도 한 번만 쓴다")
    func 종료_두_번() async throws {
        let directory = ClipFixture.directory()
        let recorder = ClipRecorder<TestFrame>(directory: directory, stamp: "s")
        for (index, frame) in ClipFixture.frames(from: 0, to: 3, fps: fps).enumerated() {
            _ = try await recorder.enqueue(frame)
            if index == 90 { _ = try await recorder.accept(ClipFixture.candidate(triggeredAt: 3.0)) }
        }

        #expect(try await recorder.finish() != nil)
        #expect(try await recorder.finish() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }

    @Test("같은 이름의 앞 클립을 지우지 않는다")
    func 이름_충돌() async throws {
        let directory = ClipFixture.directory()
        // stamp는 1초 해상도다 — 세션을 바로 다시 시작하면 같은 값이 온다
        for _ in 0..<2 {
            let recorder = ClipRecorder<TestFrame>(directory: directory, stamp: "s")
            _ = try await run(
                recorder,
                frames: ClipFixture.frames(from: 0, to: 6, fps: fps),
                candidates: [90: ClipFixture.candidate(triggeredAt: 3.0)]
            )
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == ["s-1.mov", "s-2.mov"])
    }

    @Test("경계가 딱 떨어지지 않아도 구간 밖 프레임은 들어가지 않는다")
    func 비정수_경계() async throws {
        let recorder = ClipRecorder<TestFrame>(directory: ClipFixture.directory(), stamp: "s")
        // 91/30 = 3.0333... — 구간 경계가 부동소수로 정확히 표현되지 않는다
        let triggeredAt = 91.0 / 30.0
        let clips = try await run(
            recorder,
            frames: ClipFixture.frames(from: 0, to: 7, fps: fps),
            candidates: [91: ClipFixture.candidate(triggeredAt: triggeredAt)]
        )

        let clip = try #require(clips.first)
        // 이상값은 121장이지만 경계 한 장은 어느 쪽으로든 갈 수 있다
        #expect(clip.frameCount >= 120)
        #expect(clip.frameCount <= 121)
        // 벗어나면 안 되는 것: 구간 밖 프레임이 들어오는 것
        #expect(clip.startedAt >= triggeredAt - 2.0)
        #expect(clip.startedAt + clip.duration <= triggeredAt + 2.0)
    }

    @Test("버퍼는 preRoll과 여유만큼만 들고 있는다")
    func 버퍼_창() async throws {
        let recorder = ClipRecorder<TestFrame>(
            profile: .default, margin: 1.0, directory: ClipFixture.directory(), stamp: "s"
        )
        for frame in ClipFixture.frames(from: 0, to: 10, fps: fps) {
            _ = try await recorder.enqueue(frame)
        }
        // 창 3초, 30fps. 경계(7.0초)는 버려지므로 7.0333~10.0의 90장이다
        let count = await recorder.bufferedFrameCount
        #expect(count == 90)
    }
}
