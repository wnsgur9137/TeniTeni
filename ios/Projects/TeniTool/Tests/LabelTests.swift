import AVFoundation
import Foundation
import Testing
@testable import TeniToolKit

// MARK: - 자기 일치도

/// 게이트 검출률의 분모를 사람이 만든다. 그 사람이 얼마나 정확한지
/// 모르면 검출률이 낮게 나왔을 때 도구를 탓하게 된다.
@Suite("자기 일치도")
struct AgreementTests {

    @Test("완전히 같으면 차이 0")
    func 동일() {
        let a = Agreement.compare([36, 216, 396], [36, 216, 396])
        #expect(a.pairs.count == 3)
        #expect(a.meanAbsoluteDifference == 0)
        #expect(a.maxDifference == 0)
        #expect(a.withinTolerance)
    }

    @Test("평균 절대 차이를 낸다")
    func 평균_차이() {
        let a = Agreement.compare([36, 216, 396], [37, 214, 396])
        // 차이 1, 2, 0 → 평균 1.0
        #expect(a.meanAbsoluteDifference == 1.0)
        #expect(a.maxDifference == 2)
        #expect(a.withinTolerance)
    }

    /// 하나라도 ±3을 넘으면 기준 미달이다. 평균이 낮아도 마찬가지 —
    /// 그 타구 하나가 검출률에서 빠진다.
    @Test("하나라도 허용오차를 넘으면 미달")
    func 허용오차_초과() {
        let a = Agreement.compare([36, 216, 396], [36, 216, 402])
        #expect(a.maxDifference == 6)
        #expect(!a.withinTolerance)
        #expect(a.meanAbsoluteDifference == 2.0)   // 평균은 기준 안
    }

    @Test("정확히 3프레임 차이는 통과")
    func 경계() {
        #expect(Agreement.compare([36], [39]).withinTolerance)
        #expect(!Agreement.compare([36], [40]).withinTolerance)
    }

    @Test("한쪽에서만 센 타구는 미매칭으로 남는다")
    func 누락() {
        let a = Agreement.compare([36, 216, 396], [36, 396])
        #expect(a.pairs.count == 2)
        #expect(a.unmatchedFirst == [216])
        #expect(a.unmatchedSecond.isEmpty)
        #expect(!a.withinTolerance, "누락이 있으면 일치한다고 할 수 없다")
    }

    @Test("반대쪽 누락도 잡는다")
    func 누락_반대() {
        let a = Agreement.compare([36], [36, 216])
        #expect(a.unmatchedSecond == [216])
        #expect(!a.withinTolerance)
    }

    /// 좁게 잡으면 많이 어긋난 짝이 전부 미매칭이 되어
    /// 얼마나 어긋났는지 알 수 없다.
    @Test("탐색 폭 안이면 많이 어긋나도 짝을 짓는다")
    func 탐색_폭() {
        let a = Agreement.compare([36], [56], searchWindow: 30)
        #expect(a.pairs.count == 1)
        #expect(a.maxDifference == 20)
        #expect(!a.withinTolerance)

        let b = Agreement.compare([36], [100], searchWindow: 30)
        #expect(b.pairs.isEmpty)
        #expect(b.unmatchedFirst == [36])
    }

    @Test("가까운 것끼리 짝짓는다")
    func 최근접() {
        let a = Agreement.compare([36, 40], [41, 35])
        #expect(a.pairs.count == 2)
        // 36↔35, 40↔41 이어야 한다
        #expect(a.pairs.contains { $0.first == 36 && $0.second == 35 })
        #expect(a.pairs.contains { $0.first == 40 && $0.second == 41 })
    }

    @Test("둘 다 비어 있으면 차이 0")
    func 빈_입력() {
        let a = Agreement.compare([], [])
        #expect(a.pairs.isEmpty)
        #expect(a.meanAbsoluteDifference == 0)
        #expect(a.withinTolerance)
    }
}

// MARK: - 프레임 선택

@Suite("시트 프레임 선택")
struct FrameSelectionTests {

    @Test("around가 있으면 연속으로 뽑는다")
    func 연속() {
        let frames = ContactSheet.frameNumbers(
            totalFrames: 576, around: 36, span: 5, stride: 30
        )
        #expect(frames == Array(31...41))
    }

    @Test("영상 경계를 넘지 않는다")
    func 경계_클램프() {
        #expect(ContactSheet.frameNumbers(totalFrames: 100, around: 2, span: 5, stride: 30)
                == Array(0...7))
        #expect(ContactSheet.frameNumbers(totalFrames: 100, around: 98, span: 5, stride: 30)
                == Array(93...99))
    }

    @Test("around가 없으면 간격으로 훑는다")
    func 간격() {
        let frames = ContactSheet.frameNumbers(
            totalFrames: 300, around: nil, span: 5, stride: 100
        )
        #expect(frames == [0, 100, 200])
    }

    @Test("빈 영상은 빈 목록")
    func 빈_영상() {
        #expect(ContactSheet.frameNumbers(totalFrames: 0, around: nil, span: 5, stride: 30).isEmpty)
    }
}

// MARK: - 프레임 번호 정확성

/// **시트의 프레임 번호가 analyze의 프레임 번호와 같아야 한다.**
/// 다르면 사람이 찍은 라벨과 검출 결과가 다른 체계를 쓰게 되고
/// 임팩트 매칭이 통째로 밀린다.
///
/// AVAssetImageGenerator(시간 기반 탐색)를 쓰면 실제로 약 6프레임
/// 어긋났다. 그래서 AVAssetReader 순차 읽기로 바꿨다.
@Suite("프레임 번호 정확성")
struct FrameAccuracyTests {

    /// 합성 영상을 만들어 공이 처음 나타나는 프레임을 찾는다.
    @Test("공이 정답 임팩트 프레임부터 나타난다")
    func 프레임_정확성() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "teni-frame-accuracy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let movie = directory.appending(path: "clip.mov")
        let command = try Synth.parse([
            "--out", movie.path, "--exposure", "1/1000", "--fps", "120",
            "--hits", "1", "--hit-interval", "0.4", "--height", "256", "--noise", "0",
        ])
        let plan = try SynthPlan(command: command)
        let output = plan.render()
        try VideoWriter(
            url: movie, width: plan.camera.widthPx, height: plan.camera.heightPx, fps: plan.fps
        ).write(frames: output.frames)

        let impact = output.groundTruth.groundTruth.impactFrames[0]

        // 임팩트 전후를 뽑아 공 유무를 본다
        let wanted = Set((impact - 3)...(impact + 3))
        let asset = AVURLAsset(url: movie)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let sheet = ContactSheet(columns: 4, thumbnailWidth: 320)
        let images = try sheet.extractFrames(asset: asset, track: track, wanted: wanted)

        #expect(images.count == wanted.count, "요청한 프레임이 전부 나와야 한다")

        // 공은 배경보다 밝다. 밝은 화소가 있으면 공이 있는 것이다.
        func hasBall(_ frame: Int) throws -> Bool {
            let image = try #require(images[frame])
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // 배경은 sRGB 0.35 ≈ 89, 공은 0.95 ≈ 242.
            // **알파 채널(255)을 세면 안 된다** — 항상 임계를 넘는다.
            return stride(from: 0, to: pixels.count, by: 4).contains { index in
                pixels[index] > 180 || pixels[index + 1] > 180 || pixels[index + 2] > 180
            }
        }

        for frame in (impact - 3)..<impact {
            #expect(try !hasBall(frame), "프레임 \(frame)은 타구 전이므로 공이 없어야 한다")
        }
        for frame in impact...(impact + 3) {
            #expect(try hasBall(frame), "프레임 \(frame)은 타구 후이므로 공이 있어야 한다")
        }
    }
}

// MARK: - 인자

@Suite("label 인자")
struct LabelArgumentTests {

    @Test("--sheet도 --mark도 없으면 거부")
    func 동작_없음() {
        #expect(throws: (any Error).self) { try Label.parse(["/dev/null"]) }
    }

    @Test("--compare만 있고 --with가 없으면 거부")
    func 비교_개수() {
        #expect(throws: (any Error).self) {
            try Label.parse(["--compare", "/dev/null"])  // --with 없음
        }
    }

    @Test("프레임 목록을 해석한다", arguments: [
        ("36,216,396", [36, 216, 396]),
        ("396, 36, 216", [36, 216, 396]),
        ("36 216 396", [36, 216, 396]),
        ("36", [36]),
    ])
    func 프레임_해석(_ input: String, _ expected: [Int]) throws {
        let command = try Label.parse(["/dev/null", "--mark", input])
        #expect(command.parseFrames(input) == expected)
    }

    @Test("해석할 수 없는 --mark는 거부")
    func 잘못된_mark() {
        #expect(throws: (any Error).self) {
            try Label.parse(["/dev/null", "--mark", "abc"])
        }
    }
}
