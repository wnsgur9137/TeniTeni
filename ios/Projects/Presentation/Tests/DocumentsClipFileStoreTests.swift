import Domain
import Foundation
import Testing
import TeniVision
@testable import Presentation

/// 실제 파일을 지우는 쪽. **이 PR에서 가장 위험한 코드다** — 빈 이름
/// 가드가 없으면 `Documents`를 통째로 지우려 든다.
///
/// 임시 디렉터리에서 돈다. 실기기가 필요 없다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 1
@Suite("클립 파일 삭제")
struct DocumentsClipFileStoreTests {

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "del-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in directory: URL) throws {
        try Data([0]).write(to: directory.appending(path: name))
    }

    private func exists(_ name: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }

    private func makeStore(_ directory: URL) -> DocumentsClipFileStore {
        DocumentsClipFileStore(
            directory: directory,
            sidecars: OverlaySidecarStore(directory: directory)
        )
    }

    @Test("영상을 지운다")
    func 영상() async throws {
        let directory = try makeDirectory()
        try write("a.mov", in: directory)
        await makeStore(directory).remove(fileName: "a.mov")
        #expect(exists("a.mov", in: directory) == false)
    }

    /// 사이드카는 클립과 수명이 같다(#121 선택지 1). 남겨도 짝이 안 맞아
    /// 거부되지만 **용량을 먹는다** — #124가 다루는 바로 그 용량이다.
    @Test("오버레이 사이드카도 함께 지운다")
    func 사이드카() async throws {
        let directory = try makeDirectory()
        try write("a.mov", in: directory)
        try write("a.mov.overlay.json", in: directory)
        try write("a.mov.overlay.error", in: directory)

        await makeStore(directory).remove(fileName: "a.mov")

        #expect(exists("a.mov", in: directory) == false)
        #expect(exists("a.mov.overlay.json", in: directory) == false)
        #expect(exists("a.mov.overlay.error", in: directory) == false)
    }

    /// ⚠️ **가드가 없으면 `Documents`를 통째로 지우려 든다.**
    /// `ClipLocator`와 같은 함정이고 여기서는 결과가 훨씬 나쁘다.
    @Test("빈 이름은 디렉터리를 건드리지 않는다")
    func 빈_이름() async throws {
        let directory = try makeDirectory()
        try write("a.mov", in: directory)
        try write("b.mov", in: directory)

        await makeStore(directory).remove(fileName: "")

        // 디렉터리와 그 안의 것이 **그대로** 있어야 한다.
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(exists("a.mov", in: directory))
        #expect(exists("b.mov", in: directory))
    }

    /// 파일이 **이미 없는 것은 실패가 아니다** — 사용자가 파일 앱에서
    /// 지웠거나 iOS가 정리했을 수 있다(#120). 결과는 같다: 그 파일은 없다.
    @Test("없는 파일을 지워도 조용히 끝난다")
    func 없는_파일() async throws {
        let directory = try makeDirectory()
        await makeStore(directory).remove(fileName: "없다.mov")
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("영상만 있고 사이드카가 없어도 끝난다")
    func 사이드카_없음() async throws {
        let directory = try makeDirectory()
        try write("a.mov", in: directory)
        await makeStore(directory).remove(fileName: "a.mov")
        #expect(exists("a.mov", in: directory) == false)
    }

    /// 다른 클립의 파일을 건드리면 **지우지 않은 영상이 사라진다.**
    @Test("다른 클립의 파일은 건드리지 않는다")
    func 다른_클립() async throws {
        let directory = try makeDirectory()
        try write("a.mov", in: directory)
        try write("a.mov.overlay.json", in: directory)
        try write("b.mov", in: directory)
        try write("b.mov.overlay.json", in: directory)

        await makeStore(directory).remove(fileName: "a.mov")

        #expect(exists("a.mov", in: directory) == false)
        #expect(exists("a.mov.overlay.json", in: directory) == false)
        #expect(exists("b.mov", in: directory))
        #expect(exists("b.mov.overlay.json", in: directory))
    }
}
