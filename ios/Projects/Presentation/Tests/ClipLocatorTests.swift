import Foundation
import Testing
@testable import Presentation

@Suite("클립 위치 해석")
struct ClipLocatorTests {

    private let directory = URL(filePath: "/tmp/teniteni-locator-test")

    @Test("있는 파일은 URL로 돌아온다")
    func 존재() {
        let locator = ClipLocator(directory: directory) { $0.lastPathComponent == "a.mov" }

        #expect(locator.url(for: "a.mov") == directory.appending(path: "a.mov"))
    }

    @Test("없는 파일은 nil이다")
    func 부재() {
        // 레코드는 남고 파일만 지워질 수 있다. 그 경우를 **열기 전에**
        // 알아야 플레이어 오류 문구가 아니라 설명을 보여줄 수 있다.
        let locator = ClipLocator(directory: directory) { _ in false }

        #expect(locator.url(for: "a.mov") == nil)
    }

    @Test("빈 이름은 디렉터리를 가리키지 않는다")
    func 빈_이름() {
        // 빈 이름을 그대로 붙이면 디렉터리 자신이 되고, 디렉터리는
        // 존재하므로 "파일이 있다"가 되어 플레이어가 받는다.
        // `exists`가 **무엇에든 참**을 주는데도 nil이어야 한다. 가드를
        // 지우면 디렉터리 URL이 돌아와 이 기대가 깨진다.
        let locator = ClipLocator(directory: directory) { _ in true }

        #expect(locator.url(for: "") == nil)
    }

    @Test("실제 파일 시스템에서 동작한다")
    func 실제_파일() throws {
        let root = URL.temporaryDirectory.appending(path: "teniteni-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let locator = ClipLocator(directory: root)
        #expect(locator.url(for: "clip.mov") == nil)

        try Data("x".utf8).write(to: root.appending(path: "clip.mov"))
        #expect(locator.url(for: "clip.mov") == root.appending(path: "clip.mov"))
    }
}
