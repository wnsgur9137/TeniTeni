import ArgumentParser
import Foundation
import TeniVision

/// 정답을 아는 합성 영상을 만든다.
///
/// 실기기·코트가 막힌 상황에서 0-C 도구를 검증할 유일한 수단이다.
/// 게이트 판정에는 쓰지 않는다 — 분모는 사람이 센 실제 타구다
/// (docs/02-설계/CAPTURE-PROTOCOL.md 5.5절).
public struct Synth: ParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "synth",
        abstract: "정답 JSON이 딸린 합성 테니스 영상 생성",
        discussion: """
            모션 블러는 노출 구간 안에서 하위 프레임을 선형 공간에서 누적해 만듭니다.
            블러 길이는 공 속도 × 노출 시간으로, 촬영 프로토콜 5.3절의 표를 재현합니다.

            예: teni synth --exposure 1/1000 --out clip.mov
                teni synth --exposure 1/60 --hits 5 --out blurry.mov
            """
    )

    // MARK: 출력

    @Option(name: .shortAndLong, help: "출력 .mov 경로. 정답 JSON은 같은 이름의 .json으로 나란히 씁니다.")
    var out: String

    @Option(help: "정답 JSON의 clipId. 생략하면 파일명에서 만듭니다.")
    var clipId: String?

    // MARK: 카메라

    @Option(help: "가로 해상도 (px)")
    var width: Int = 1920

    @Option(help: "세로 해상도 (px)")
    var height: Int = 1080

    @Option(help: "프레임레이트")
    var fps: Double = 120

    @Option(help: "노출 시간. 1/1000 같은 분수 표기를 받습니다.")
    var exposure: Exposure = Exposure(seconds: 1.0 / 1000, label: "1/1000")

    @Option(help: "카메라–피사체 거리 (m)")
    var distance: Double = 6

    @Option(help: "렌즈 높이 (m)")
    var cameraHeight: Double = 1.1

    @Option(help: "수평 시야각 (도)")
    var fov: Double = 70

    // MARK: 타구

    @Option(help: "타구 횟수")
    var hits: Int = 3

    @Option(help: "타구 간격 (초)")
    var hitInterval: Double = 1.5

    @Option(help: "공 속력 (km/h)")
    var ballSpeed: Double = 100

    @Option(help: "발사각 (도). 양수면 위로 칩니다.")
    var launchAngle: Double = 12

    @Option(help: "타구 높이 (m)")
    var contactHeight: Double = 1.0

    // MARK: 장면

    @Option(help: "배경 밝기 (0~1)")
    var background: Double = 0.35

    @Option(help: "공 밝기 (0~1)")
    var ballBrightness: Double = 0.95

    @Option(help: "센서 노이즈 표준편차 (0이면 없음)")
    var noise: Double = 0.01

    @Option(help: "난수 시드. 같은 시드는 같은 영상을 냅니다.")
    var seed: UInt64 = 1

    @Option(help: "노출 구간당 하위 표본 수. 생략하면 블러 길이에서 자동 결정합니다.")
    var blurSamples: Int?

    // MARK: 실행

    public init() {}

    public func validate() throws {
        guard width > 0, height > 0 else {
            throw ValidationError("해상도는 양수여야 합니다")
        }
        guard fps > 0 else { throw ValidationError("fps는 양수여야 합니다") }
        guard exposure.seconds > 0 else { throw ValidationError("노출은 양수여야 합니다") }
        guard exposure.seconds <= 1 / fps else {
            throw ValidationError(
                "노출(\(exposure.label) = \(exposure.seconds)s)이 프레임 간격(1/\(fps) = \(1 / fps)s)보다 깁니다. 물리적으로 불가능합니다."
            )
        }
        guard distance > 0, fov > 0, fov < 180 else {
            throw ValidationError("거리와 시야각이 유효하지 않습니다")
        }
        guard hits > 0 else { throw ValidationError("타구 횟수는 1 이상이어야 합니다") }
        guard (0...1).contains(background), (0...1).contains(ballBrightness) else {
            throw ValidationError("밝기는 0~1이어야 합니다")
        }
        guard noise >= 0 else { throw ValidationError("노이즈는 음수가 될 수 없습니다") }
        if let blurSamples, blurSamples < 1 {
            throw ValidationError("하위 표본 수는 1 이상이어야 합니다")
        }
    }

    public func run() throws {
        let plan = try SynthPlan(command: self)
        let movieURL = URL(fileURLWithPath: out)

        // 프레임을 만드는 즉시 인코더로 넘긴다. 배열로 쌓으면 1080p에서
        // 1.5GB가 되어 스윕이 메모리 부족으로 죽는다 (이슈 #31).
        let session = try VideoWriter(
            url: movieURL, width: width, height: height, fps: fps
        ).makeSession()
        let truth = try plan.render { _, frame in try session.append(frame) }
        try session.finish()

        let jsonURL = movieURL.deletingPathExtension().appendingPathExtension("json")
        try truth.write(to: jsonURL)

        let diameter = plan.camera.ballDiameterPx
        let referenceBlur = plan.referenceBlurLengthPx
        print("""
            생성 완료
              영상      \(movieURL.path)
              정답      \(jsonURL.path)
              프레임    \(plan.frameCount) (\(String(format: "%.2f", Double(plan.frameCount) / fps))초 @ \(fps)fps)
              공 지름   \(String(format: "%.2f", diameter)) px
              노출      \(exposure.label) → 블러 \(String(format: "%.2f", referenceBlur)) px (공 지름의 \(String(format: "%.0f", referenceBlur / diameter * 100))%)
              하위 표본 \(plan.blurSampleCount)장/프레임
              타구      \(truth.groundTruth.impactFrames.map(String.init).joined(separator: ", "))
            """)
    }
}
