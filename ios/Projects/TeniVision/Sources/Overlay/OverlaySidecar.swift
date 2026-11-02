import CoreGraphics
import Foundation

/// 오버레이 한 프레임.
public struct OverlayFrame: Sendable, Equatable, Codable {
    /// **클립 기준 절대초**(= 비디오 트랙의 PTS).
    ///
    /// `AVPlayer.currentTime()`과 `Swing.startSeconds`가 같은 시계를 쓴다.
    /// 첫 프레임을 0으로 당기지 않는 이유는 `OverlayBaker`에 적었다.
    public let seconds: Double
    /// 신체 관절. 관측에 없던 관절은 **키가 없다** — 0으로 채우지 않는다.
    public let joints: [PoseJoint: PoseJointSample]
    /// 라켓 헤드. `nil`이면 그 프레임은 **선을 끊는다.**
    public let racketHead: RacketHead?

    public init(
        seconds: Double,
        joints: [PoseJoint: PoseJointSample],
        racketHead: RacketHead?
    ) {
        self.seconds = seconds
        self.joints = joints
        self.racketHead = racketHead
    }
}

/// 클립 하나의 오버레이 데이터. 클립 파일 옆 `.overlay.json`에 둔다.
///
/// ## 왜 파일인가
///
/// SwiftData에 넣으면 보관함이 읽는 DB가 프레임 수백 개 × 관절 19개로
/// 무거워진다. 보관함은 탭 진입마다 그 DB를 읽는다(SPEC-0116).
///
/// 레코드와 파일이 어긋날 수 있다는 단점은 **이미 있는 문제**이고
/// (#120) 사이드카가 없으면 "분석 전"으로 떨어지면 된다 —
/// **없는 것이 정상 상태 중 하나다.**
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md 선택지 1
public struct OverlaySidecar: Sendable, Equatable, Codable {

    /// 지금 구현이 쓰는 포맷 번호.
    ///
    /// 볼 궤적(0-C 게이트 후)과 라인(1-F 후)이 나중에 들어오므로 **포맷이
    /// 바뀔 것을 전제한다.**
    public static let currentVersion = 1

    public let version: Int
    /// 클립과 짝이 맞는지 확인용. 어긋나면 **쓰지 않는다.**
    public let clipFileName: String
    /// 클립의 **실제** fps. 발열로 강등되면 클립마다 다르다(ADR-0005) —
    /// 세션의 fps를 가정하면 오버레이가 영상과 어긋난다.
    public let frameRate: Double
    /// 영상 픽셀 크기. `RacketHeadEstimator`의 종횡비와 Canvas 변환이
    /// **같은 값을 봐야** 둘이 어긋나지 않는다.
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// 프레임 사이 **실측** 간격의 중앙값.
    ///
    /// `frameRate`는 트랙의 `nominalFrameRate`이고, 발열 강등이나 가변
    /// 프레임률에서는 실제와 다르다(ADR-0005). 그 값으로 허용 범위를
    /// 정하면 타임라인에 틈이 생겨 **오버레이가 깜빡인다.**
    ///
    /// 0이면 `frameRate`로 떨어진다 — 프레임이 하나뿐인 클립이다.
    public let frameSpacing: Double
    public let frames: [OverlayFrame]

    public init(
        version: Int = OverlaySidecar.currentVersion,
        clipFileName: String,
        frameRate: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        frames: [OverlayFrame],
        frameSpacing: Double? = nil
    ) {
        self.version = version
        self.clipFileName = clipFileName
        self.frameRate = frameRate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frames = frames
        self.frameSpacing = frameSpacing ?? Self.medianSpacing(of: frames)
    }

    /// 프레임 사이 간격의 중앙값. **평균이 아니다** — 사람을 못 찾아 빠진
    /// 구간이 평균을 통째로 끌어올린다.
    static func medianSpacing(of frames: [OverlayFrame]) -> Double {
        guard frames.count > 1 else { return 0 }
        var deltas: [Double] = []
        deltas.reserveCapacity(frames.count - 1)
        for index in 1..<frames.count {
            let delta = frames[index].seconds - frames[index - 1].seconds
            if delta > 0 { deltas.append(delta) }
        }
        guard !deltas.isEmpty else { return 0 }
        deltas.sort()
        // **하위 중앙값**을 쓴다. 짝수 개에서 상위를 집으면 빈 구간 하나가
        // 섞인 짧은 클립에서 그 큰 값이 기준이 된다 — 예: 간격이
        // [1, 2]면 2를 집고, 허용 범위가 1.5간격이 돼 **빠진 프레임을
        // 메워 버린다.**
        return deltas[(deltas.count - 1) / 2]
    }

    /// `픽셀 가로 / 픽셀 세로`. 둘 중 하나가 0이면 `nil`이다.
    public var aspect: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    /// 이 사이드카를 이 클립에 쓸 수 있는가.
    ///
    /// **버전이 다르면 거부한다.** 모르는 포맷을 "읽을 수 있는 만큼" 읽으면
    /// 빠진 필드가 기본값으로 채워져 **틀린 오버레이를 확신 있게** 보여준다.
    public func isUsable(for clipFileName: String) -> Bool {
        version == Self.currentVersion
            && self.clipFileName == clipFileName
            && frameRate > 0
            && aspect != nil
    }

    /// 주어진 시각에 가장 가까운 프레임.
    ///
    /// 보간하지 않는다 — 관절을 보간하면 **없던 자세가 생긴다.** 슬로우
    /// 모션에서 같은 프레임이 여러 번 보이는 것이 거짓보다 낫다.
    ///
    /// `frames`는 시간 순서라고 가정한다(굽는 경로가 순차로 읽는다).
    public func frame(at seconds: Double) -> OverlayFrame? {
        guard !frames.isEmpty else { return nil }
        // 간격의 **3/4**을 허용 범위로 둔다.
        //
        // 기준은 `frameSpacing`(실측 중앙값)이다. `frameRate`는
        // `nominalFrameRate`이고 발열 강등·가변 프레임률에서 실제와 달라
        // **타임라인에 틈이 생겨 오버레이가 깜빡인다.**
        //
        // 3/4이어도 엉뚱한 프레임을 집지 않는다: 옆 프레임은 1간격 밖에
        // 있으므로 0.75 안에 들어오지 못한다. 그래서 **한 프레임이 비어 있는
        // 구간(사람을 못 찾은 프레임)은 여전히 `nil`로 떨어진다.**
        let spacing = frameSpacing > 0 ? frameSpacing : (frameRate > 0 ? 1 / frameRate : 0)
        let tolerance = 0.75 * spacing
        var best: OverlayFrame?
        var bestDistance = Double.infinity
        for frame in frames {
            let distance = abs(frame.seconds - seconds)
            if distance < bestDistance {
                bestDistance = distance
                best = frame
            } else if frame.seconds > seconds {
                // 시간 순서이므로 멀어지기 시작하면 더 볼 것이 없다.
                break
            }
        }
        guard bestDistance <= tolerance else { return nil }
        return best
    }
}
