import ArgumentParser
import AVFoundation
import Foundation

/// 임팩트 프레임을 사람이 찍는다. 게이트 검출률의 **분모**를 만드는 도구다.
///
/// 터미널에 영상이 안 나오므로 컨택트 시트를 PNG로 뽑아 미리보기로 보고,
/// 확정한 번호를 `--mark`로 넘긴다. 설계 근거는
/// docs/07-기획/SPEC-0008-label-tool.md.
public struct Label: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "label",
        abstract: "임팩트 프레임을 수동으로 기록합니다",
        discussion: """
            세 단계로 씁니다.

              1. teni label clip.mov --sheet
                 전체를 성기게 훑어 타구 구간을 찾습니다.

              2. teni label clip.mov --sheet --around 36 --span 20
                 그 구간을 프레임 단위로 확대합니다.

              3. teni label clip.mov --mark 36,216,396 --out truth.json
                 확정한 번호를 JSON으로 저장합니다.

            같은 클립을 두 번 라벨링했으면 자기 일치도를 잴 수 있습니다.
              teni label --compare pass1.json --with pass2.json
            게이트 허용오차(±3프레임)가 현실적인지 판단하는 근거가 됩니다.
            """
    )

    @Argument(help: "대상 영상 경로. --compare만 쓸 때는 생략합니다.")
    var video: String?

    // MARK: 시트

    @Flag(help: "컨택트 시트 PNG를 생성합니다")
    var sheet = false

    @Option(help: "이 프레임 주변을 프레임 단위로 뽑습니다")
    var around: Int?

    @Option(help: "--around 기준 앞뒤 프레임 수")
    var span: Int = 15

    @Option(help: "--around가 없을 때 훑는 간격 (프레임)")
    var stride: Int = 30

    @Option(help: "격자 열 수")
    var columns: Int = 6

    @Option(help: "썸네일 가로 크기 (px). 공이 작으면 키우세요")
    var thumbWidth: Int = 320

    // MARK: 기록

    @Option(help: "임팩트 프레임 목록. 쉼표로 구분합니다 (예: 36,216,396)")
    var mark: String?

    @Option(help: "몇 번째 라벨링인가. 자기 일치도 측정에 씁니다")
    var pass: Int = 1

    @Option(help: "라벨링 메모")
    var note: String?

    // MARK: 비교

    @Option(help: "비교할 첫 번째 라벨링 JSON")
    var compare: String?

    @Option(help: "비교할 두 번째 라벨링 JSON")
    var with: String?

    // MARK: 공통

    @Option(name: .shortAndLong, help: "출력 경로")
    var out: String?

    @Option(help: "촬영 조건 — 장소")
    var location: String = "outdoor"

    @Option(help: "촬영 조건 — 조명")
    var light: String = "sunny"

    @Option(help: "촬영 조건 — 배경")
    var background: String = "simple"

    public init() {}

    public func validate() throws {
        if compare != nil || with != nil {
            guard let compare, let with else {
                throw ValidationError("--compare와 --with를 함께 지정하세요")
            }
            for path in [compare, with] where !FileManager.default.fileExists(atPath: path) {
                throw ValidationError("파일을 찾을 수 없습니다: \(path)")
            }
            return
        }

        guard let video else {
            throw ValidationError("영상 경로가 필요합니다")
        }
        guard FileManager.default.fileExists(atPath: video) else {
            throw ValidationError("영상을 찾을 수 없습니다: \(video)")
        }
        guard sheet || mark != nil else {
            throw ValidationError("--sheet 또는 --mark 중 하나가 필요합니다")
        }
        guard columns > 0, thumbWidth > 0, span >= 0, stride > 0 else {
            throw ValidationError("격자·간격 값이 유효하지 않습니다")
        }
        if let mark {
            guard !parseFrames(mark).isEmpty else {
                throw ValidationError("--mark를 해석할 수 없습니다: \(mark)")
            }
        }
    }

    public func run() async throws {
        if let compare, let with {
            try runCompare(compare, with)
            return
        }
        let videoURL = URL(fileURLWithPath: video!)
        if sheet { try await runSheet(videoURL) }
        if let mark { try runMark(videoURL, frames: parseFrames(mark)) }
    }

    // MARK: 프레임 목록 해석

    func parseFrames(_ text: String) -> [Int] {
        text.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 >= 0 }
            .sorted()
    }

    // MARK: 시트

    private func runSheet(_ videoURL: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ContactSheet.Failure.noVideoTrack
        }
        let fps = Double(try await track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration).seconds
        let totalFrames = Int((duration * fps).rounded())

        let frames = ContactSheet.frameNumbers(
            totalFrames: totalFrames, around: around, span: span, stride: stride
        )
        guard !frames.isEmpty else {
            print("뽑을 프레임이 없습니다 (총 \(totalFrames)프레임)")
            return
        }

        let suffix = around.map { "around\($0)" } ?? "overview"
        let outputURL = out.map { URL(fileURLWithPath: $0) }
            ?? videoURL.deletingPathExtension()
                .appendingPathExtension("sheet-\(suffix).png")

        let renderer = ContactSheet(columns: columns, thumbnailWidth: thumbWidth)
        let result = try await renderer.render(videoURL: videoURL, frames: frames, to: outputURL)

        print("""
            시트 생성
              영상      \(videoURL.lastPathComponent) (\(totalFrames)프레임, \(String(format: "%.0f", fps))fps)
              범위      \(frames.first!) ~ \(frames.last!) (\(frames.count)장\(around == nil ? ", \(stride)프레임 간격" : ", 연속"))
              격자      \(columns)열 × \(Int(result.sheetSize.width))×\(Int(result.sheetSize.height))px
              출력      \(outputURL.path)

            미리보기로 열어 임팩트 프레임 번호를 확인하세요.
              open "\(outputURL.path)"
            """)

        if around == nil {
            print("""

                다음 단계 — 찾은 구간을 프레임 단위로 확대합니다.
                  teni label "\(videoURL.path)" --sheet --around <프레임> --span \(span)
                """)
        }
    }

    // MARK: 기록

    private func runMark(_ videoURL: URL, frames: [Int]) throws {
        let outputURL = out.map { URL(fileURLWithPath: $0) }
            ?? videoURL.deletingPathExtension().appendingPathExtension("truth.json")

        // 촬영 메타가 옆에 있으면 가져온다. 없으면 빈 값으로 둔다 —
        // 지어내면 #9 집계가 틀린 조건으로 묶는다.
        let sidecar = videoURL.deletingPathExtension().appendingPathExtension("json")
        let capture = (try? loadCapture(sidecar))
            ?? GroundTruth.Capture(
                fps: 0, resolution: "unknown", exposureDuration: "unknown",
                distanceM: 0, heightM: 0, videoFieldOfView: 0
            )

        let labels = LabelSet(
            clipId: videoURL.deletingPathExtension().lastPathComponent,
            condition: .init(location: location, light: light, background: background),
            capture: capture,
            groundTruth: .init(impactFrames: frames),
            labeling: .init(labeledAt: Date(), pass: pass, note: note)
        )
        try labels.write(to: outputURL)

        print("""
            라벨 저장
              타구      \(frames.count)개 — \(frames.map(String.init).joined(separator: ", "))
              회차      \(pass)
              출력      \(outputURL.path)
            """)
        if capture.fps == 0 {
            print("  ⚠️ 촬영 메타를 찾지 못했습니다 (\(sidecar.lastPathComponent)). capture가 비어 있습니다")
        }
        if pass == 1 {
            print("""

                자기 일치도를 재려면 같은 클립을 다시 라벨링하세요.
                  teni label "\(videoURL.path)" --mark <프레임들> --pass 2 --out pass2.json
                  teni label --compare "\(outputURL.path)" --with pass2.json
                """)
        }
    }

    private func loadCapture(_ url: URL) throws -> GroundTruth.Capture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // synth 출력과 label 출력 모두 capture를 같은 자리에 둔다
        if let truth = try? decoder.decode(GroundTruth.self, from: Data(contentsOf: url)) {
            return truth.capture
        }
        return try decoder.decode(LabelSet.self, from: Data(contentsOf: url)).capture
    }

    // MARK: 비교

    private func runCompare(_ first: String, _ second: String) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sets = try [first, second].map {
            try decoder.decode(LabelSet.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let agreement = Agreement.compare(
            sets[0].groundTruth.impactFrames,
            sets[1].groundTruth.impactFrames
        )

        print("""
            자기 일치도
              회차      \(sets[0].labeling.pass) vs \(sets[1].labeling.pass)
              타구      \(sets[0].groundTruth.impactFrames.count) vs \(sets[1].groundTruth.impactFrames.count)
              짝지음    \(agreement.pairs.count)개
            """)

        for pair in agreement.pairs {
            let flag = pair.difference > Agreement.toleranceFrames ? " ⚠️" : ""
            print("    \(pair.first) ↔ \(pair.second)   차이 \(pair.difference)\(flag)")
        }
        if !agreement.unmatchedFirst.isEmpty {
            print("    첫 번째에만: \(agreement.unmatchedFirst.map(String.init).joined(separator: ", "))")
        }
        if !agreement.unmatchedSecond.isEmpty {
            print("    두 번째에만: \(agreement.unmatchedSecond.map(String.init).joined(separator: ", "))")
        }

        let fps = sets[0].capture.fps
        let ms = fps > 0 ? String(format: " (%.1f ms)", agreement.meanAbsoluteDifference / fps * 1000) : ""
        print("""
              ─────
              평균 절대 차이  \(String(format: "%.2f", agreement.meanAbsoluteDifference))프레임\(ms)
              최대 차이       \(agreement.maxDifference)프레임
              게이트 기준     ±\(Agreement.toleranceFrames)프레임 — \(agreement.withinTolerance ? "충족" : "미달")
            """)

        if !agreement.withinTolerance {
            print("""

                기준 미달입니다. 사람의 라벨링 정밀도가 게이트 허용오차보다 낮다는
                뜻이고, 그러면 검출기가 정확해도 검출률이 낮게 나옵니다.

                이 도구는 재기만 합니다. 기준을 넓힐지는 사람이 정합니다 —
                docs/02-설계/CAPTURE-PROTOCOL.md 5.5절.
                """)
        }
    }
}
