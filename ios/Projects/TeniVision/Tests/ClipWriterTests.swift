import AVFoundation
import Foundation
import Testing
@testable import TeniVision

@Suite("클립 파일 쓰기")
struct ClipWriterTests {

    @Test("프레임이 없으면 거부한다")
    func 빈_입력() {
        let url = ClipFixture.directory().appending(path: "empty.mov")
        #expect(throws: ClipWriter.Failure.emptyClip) {
            _ = try ClipWriter().write([TestFrame](), to: url)
        }
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("쓴 프레임이 파일에 그대로 들어간다")
    func 프레임_수() async throws {
        let frames = ClipFixture.frames(from: 0, to: 1, fps: 30)  // 31장
        let url = ClipFixture.directory().appending(path: "clip.mov")
        let written = try ClipWriter().write(frames, to: url)

        #expect(written.frameCount == 31)
        let counted = try await sampleCount(of: url)
        #expect(counted == 31)
    }

    @Test("PTS 0은 첫 프레임의 시각이다")
    func 원점() throws {
        let frames = ClipFixture.frames(from: 2, to: 3, fps: 30)
        let url = ClipFixture.directory().appending(path: "clip.mov")
        let written = try ClipWriter().write(frames, to: url)

        #expect(written.startedAt == 2.0)
        #expect(abs(written.duration - 1.0) < 0.001)
    }

    @Test("파일 길이가 프레임 구간과 맞는다")
    func 길이() async throws {
        let frames = ClipFixture.frames(from: 0, to: 2, fps: 30)  // 61장, 구간 2.0초
        let url = ClipFixture.directory().appending(path: "clip.mov")
        _ = try ClipWriter().write(frames, to: url)

        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        // 자산 길이는 **마지막 프레임의 표시 시간까지** 포함하므로 구간보다
        // 한 프레임만큼 길다. 어느 쪽으로도 벗어나면 안 된다.
        #expect(duration >= 2.0)
        #expect(duration <= 2.0 + 2.0 / 30.0)
    }

    @Test("없는 디렉터리를 만든다")
    func 디렉터리_생성() throws {
        let url = ClipFixture.directory().appending(path: "a/b/clip.mov")
        _ = try ClipWriter().write(ClipFixture.frames(from: 0, to: 0.2, fps: 30), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("시각이 역행하면 오류다")
    func 역행() throws {
        let buffer = ClipFixture.pixelBuffer()
        let frames = [
            TestFrame(seconds: 0.0, buffer: buffer),
            TestFrame(seconds: 0.1, buffer: buffer),
            TestFrame(seconds: 0.05, buffer: buffer),
        ]
        let url = ClipFixture.directory().appending(path: "clip.mov")
        #expect(throws: ClipWriter.Failure.timestampWentBackwards) {
            _ = try ClipWriter().write(frames, to: url)
        }
    }

    @Test("있는 파일을 덮어쓰지 않는다")
    func 덮어쓰기_금지() throws {
        let url = ClipFixture.directory().appending(path: "clip.mov")
        let frames = ClipFixture.frames(from: 0, to: 0.2, fps: 30)
        _ = try ClipWriter().write(frames, to: url)
        let before = try Data(contentsOf: url).count

        #expect(throws: ClipWriter.Failure.fileAlreadyExists("clip.mov")) {
            _ = try ClipWriter().write(frames, to: url)
        }
        // 거부만 하는 게 아니라 **앞 파일이 그대로** 있어야 한다
        #expect(try Data(contentsOf: url).count == before)
    }

    @Test("쓰다가 실패하면 덜 쓰인 파일을 남기지 않는다")
    func 실패_정리() throws {
        let buffer = ClipFixture.pixelBuffer()
        let frames = [
            TestFrame(seconds: 0.0, buffer: buffer),
            TestFrame(seconds: 0.1, buffer: buffer),
            TestFrame(seconds: 0.05, buffer: buffer),  // 역행 — 여기서 던진다
        ]
        let url = ClipFixture.directory().appending(path: "clip.mov")
        #expect(throws: ClipWriter.Failure.timestampWentBackwards) {
            _ = try ClipWriter().write(frames, to: url)
        }
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("첫 프레임보다 이른 프레임을 거부한다")
    func 첫_프레임보다_이름() throws {
        let buffer = ClipFixture.pixelBuffer()
        let url = ClipFixture.directory().appending(path: "clip.mov")
        let session = try ClipWriter.Session(
            url: url, first: TestFrame(seconds: 1.0, buffer: buffer)
        )
        defer { session.cancel() }
        // 세션은 .zero에서 시작한다 — 이것을 통과시키면 음수 PTS가 된다
        #expect(throws: ClipWriter.Failure.timestampWentBackwards) {
            try session.append(TestFrame(seconds: 0.5, buffer: buffer))
        }
    }

    @Test("프레임을 하나도 넣지 않고 닫으면 거부한다")
    func 세션_빈_종료() throws {
        let url = ClipFixture.directory().appending(path: "clip.mov")
        let session = try ClipWriter.Session(
            url: url, first: TestFrame(seconds: 0, buffer: ClipFixture.pixelBuffer())
        )
        #expect(throws: ClipWriter.Failure.emptyClip) { _ = try session.finish() }
    }
}
