import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TeniToolKit

/// `ContactSheet.render`는 사람이 임팩트 프레임을 고르는 유일한 수단이다.
/// 프레임 정확성은 [#8](https://github.com/wnsgur9137/TeniTeni/issues/8)에서
/// 픽셀로 고정했지만 **PNG 생성 자체는 덮이지 않았다** (이슈 #35).
@Suite("컨택트 시트 생성")
struct ContactSheetTests {

    /// 클립은 ClipCache가 공유한다. 시트 테스트마다 영상을 새로 만들면
    /// 게이트가 몇 분씩 늘어난다.
    private func clip() async throws -> URL {
        try await ClipCache.shared.clip(hits: 1, height: 512).movie
    }

    private func scratch(_ name: String) async -> URL {
        await ClipCache.shared.scratch().appending(path: name)
    }

    /// PNG의 실제 크기를 읽는다. 반환값만 믿으면 파일이 깨져도 통과한다.
    private func pngSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    @Test("PNG가 만들어지고 격자 크기와 맞는다")
    func 시트_생성() async throws {
        let movie = try await clip()
        let output = await scratch("sheet.png")

        let sheet = ContactSheet(columns: 4, thumbnailWidth: 320)
        let result = try await sheet.render(
            videoURL: movie, frames: Array(30...37), to: output
        )

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(result.frameNumbers == Array(30...37))

        // 8장을 4열로 → 2행
        let size = try #require(pngSize(output))
        #expect(size.width == 4 * 320, "4열 × 320px")
        #expect(
            size.height == Int(result.sheetSize.height),
            "반환한 크기와 실제 PNG가 달라지면 안 된다"
        )
        #expect(size.height > 0)
    }

    /// 마지막 행이 덜 찼을 때도 올바른 행 수가 나와야 한다.
    @Test("행이 덜 차도 크기가 맞는다")
    func 부분_행() async throws {
        let movie = try await clip()
        let output = await scratch("partial.png")

        let sheet = ContactSheet(columns: 4, thumbnailWidth: 200)
        // 5장을 4열로 → 2행 (둘째 행은 1칸만)
        _ = try await sheet.render(videoURL: movie, frames: [10, 11, 12, 13, 14], to: output)

        let size = try #require(pngSize(output))
        #expect(size.width == 4 * 200)

        // 2행이므로 1행짜리보다 크다
        let single = await scratch("single.png")
        _ = try await sheet.render(videoURL: movie, frames: [10, 11], to: single)
        let singleSize = try #require(pngSize(single))
        #expect(size.height > singleSize.height)
    }

    @Test("썸네일 폭을 키우면 시트도 커진다")
    func 썸네일_크기() async throws {
        let movie = try await clip()
        let small = await scratch("small.png")
        let large = await scratch("large.png")

        _ = try await ContactSheet(columns: 2, thumbnailWidth: 160)
            .render(videoURL: movie, frames: [10, 11], to: small)
        _ = try await ContactSheet(columns: 2, thumbnailWidth: 480)
            .render(videoURL: movie, frames: [10, 11], to: large)

        let smallSize = try #require(pngSize(small))
        let largeSize = try #require(pngSize(large))
        #expect(largeSize.width == 3 * smallSize.width)
        #expect(largeSize.height > smallSize.height)
    }

    /// 요청한 프레임이 영상에 없으면 조용히 넘어가지 않아야 한다.
    @Test("범위 밖 프레임은 던진다")
    func 범위_밖() async throws {
        let movie = try await clip()
        let output = await scratch("bad.png")
        let sheet = ContactSheet(columns: 2, thumbnailWidth: 160)

        await #expect(throws: (any Error).self) {
            _ = try await sheet.render(videoURL: movie, frames: [999_999], to: output)
        }
    }

    @Test("영상 트랙이 없으면 던진다")
    func 잘못된_영상() async throws {
        let fake = await scratch("fake-sheet.mov")
        try Data("not a movie".utf8).write(to: fake)
        let sheet = ContactSheet(columns: 2, thumbnailWidth: 160)

        await #expect(throws: (any Error).self) {
            _ = try await sheet.render(
                videoURL: fake, frames: [0], to: await scratch("x.png")
            )
        }
    }
}
