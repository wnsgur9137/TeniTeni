import CoreGraphics
import Foundation
import Testing
@testable import TeniVision

/// 가짜 손. `HumanHandPoseObservation`을 합성할 수 없어서 경계를 둔 것이고,
/// 그 경계가 실제로 이 정도로 좁은지가 여기서 드러난다.
private struct FakeHand: HandPoseObservable {
    var samples: [HandJoint: PoseJointSample] = [:]
    func sample(for joint: HandJoint) -> PoseJointSample? { samples[joint] }
}

/// 신체 + 손을 함께 주는 가짜 관측.
private struct FakeRacketPose: RacketPoseObservable {
    var body: [PoseJoint: PoseJointSample] = [:]
    var hands: [RacketSide: FakeHand] = [:]

    func sample(for joint: PoseJoint) -> PoseJointSample? { body[joint] }
    func hand(_ side: RacketSide) -> (any HandPoseObservable)? { hands[side] }

    /// 어깨 둘 + 오른손이 놓인 관측.
    static func standing(
        shoulderHalf: CGFloat = 0.1,
        handOffset: CGFloat = 0.05,
        shoulderConfidence: Double = 0.9
    ) -> FakeRacketPose {
        var pose = FakeRacketPose()
        pose.body[.leftShoulder] = PoseJointSample(
            point: CGPoint(x: 0.5 - shoulderHalf, y: 0.6), confidence: shoulderConfidence
        )
        pose.body[.rightShoulder] = PoseJointSample(
            point: CGPoint(x: 0.5 + shoulderHalf, y: 0.6), confidence: shoulderConfidence
        )
        pose.hands[.right] = FakeHand(samples: [
            .wrist: PoseJointSample(point: CGPoint(x: 0.5, y: 0.5), confidence: 0.9),
            .middleMCP: PoseJointSample(point: CGPoint(x: 0.5, y: 0.5 + handOffset), confidence: 0.9),
        ])
        return pose
    }
}

@Suite("오버레이 프레임 만들기")
struct OverlayFrameBuilderTests {

    private static let aspect = 16.0 / 9.0

    @Test("관절이 하나도 없으면 프레임을 만들지 않는다")
    func 빈_관측() {
        let frame = OverlayFrameBuilder.frame(
            from: FakeRacketPose(), side: .right, aspect: Self.aspect,
            at: 0, minimumConfidence: 0.3
        )
        // 관절 없는 프레임을 넣으면 사이드카가 "사람이 있었다"고 거짓을 말한다.
        #expect(frame == nil)
    }

    @Test("관절 전부를 담고 시각이 붙는다")
    func 관절_수집() throws {
        let frame = try #require(
            OverlayFrameBuilder.frame(
                from: FakeRacketPose.standing(), side: .right, aspect: Self.aspect,
                at: 1.5, minimumConfidence: 0.3
            )
        )
        #expect(frame.seconds == 1.5)
        #expect(frame.joints.count == 2)
        #expect(frame.joints[.leftShoulder] != nil)
    }

    @Test("손이 없으면 라켓 헤드가 nil이다 — 프레임은 남는다")
    func 손_없음() throws {
        var pose = FakeRacketPose.standing()
        pose.hands = [:]
        let frame = try #require(
            OverlayFrameBuilder.frame(
                from: pose, side: .right, aspect: Self.aspect, at: 0, minimumConfidence: 0.3
            )
        )
        // 스켈레톤은 그릴 수 있다. 라켓만 끊는다.
        #expect(frame.racketHead == nil)
        #expect(!frame.joints.isEmpty)
    }

    @Test("반대쪽 손만 있으면 라켓 헤드가 nil이다")
    func 반대쪽_손() throws {
        let frame = try #require(
            OverlayFrameBuilder.frame(
                from: FakeRacketPose.standing(), side: .left, aspect: Self.aspect,
                at: 0, minimumConfidence: 0.3
            )
        )
        #expect(frame.racketHead == nil)
    }

    /// 믿을 수 없는 어깨로 만든 자는 라켓 길이를 엉뚱하게 환산한다.
    @Test("어깨 신뢰도가 임계에 못 미치면 라켓 헤드가 nil이다")
    func 어깨_미달() throws {
        let frame = try #require(
            OverlayFrameBuilder.frame(
                from: FakeRacketPose.standing(shoulderConfidence: 0.1),
                side: .right, aspect: Self.aspect, at: 0, minimumConfidence: 0.3
            )
        )
        #expect(frame.racketHead == nil)
    }

    @Test("정상 입력이면 라켓 헤드가 나온다")
    func 라켓_헤드() throws {
        let aspect = Self.aspect
        let metersPerUnit = RacketHeadEstimator.shoulderMeters / (0.2 * aspect)
        let handUnits = RacketHeadEstimator.handMeters / metersPerUnit

        let frame = try #require(
            OverlayFrameBuilder.frame(
                from: FakeRacketPose.standing(handOffset: CGFloat(handUnits)),
                side: .right, aspect: aspect, at: 0, minimumConfidence: 0.3
            )
        )
        let head = try #require(frame.racketHead)
        #expect(head.confidence > OverlayFrameBuilder.racketMinimumConfidence)
        // 그립 축이 위쪽이므로 헤드는 손목보다 위에 있다.
        #expect(head.point.y > 0.5)
    }
}

@Suite("사이드카")
struct OverlaySidecarTests {

    private static func sidecar(
        version: Int = OverlaySidecar.currentVersion,
        clipFileName: String = "clip-1.mov",
        frameRate: Double = 60,
        pixelWidth: Int = 1920,
        pixelHeight: Int = 1080,
        frames: [OverlayFrame] = []
    ) -> OverlaySidecar {
        OverlaySidecar(
            version: version,
            clipFileName: clipFileName,
            frameRate: frameRate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            frames: frames
        )
    }

    private static func frame(_ seconds: Double) -> OverlayFrame {
        OverlayFrame(
            seconds: seconds,
            joints: [.rightWrist: PoseJointSample(point: CGPoint(x: 0.5, y: 0.5), confidence: 0.8)],
            racketHead: RacketHead(point: CGPoint(x: 0.6, y: 0.7), confidence: 0.5)
        )
    }

    // MARK: - 왕복

    @Test("인코딩·디코딩을 왕복한다")
    func 왕복() throws {
        let original = Self.sidecar(frames: [Self.frame(0), Self.frame(1.0 / 60)])
        #expect(original.frameSpacing > 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OverlaySidecar.self, from: data)
        #expect(decoded == original)
    }

    /// JSON을 고른 이유의 절반이 "사람이 열어 읽을 수 있다"는 것이다.
    /// 관절 딕셔너리가 배열로 인코딩되면 그 이유가 사라진다.
    @Test("관절은 JSON 객체로 인코딩된다 — 배열이 아니다")
    func 관절_객체() throws {
        let data = try JSONEncoder().encode(Self.sidecar(frames: [Self.frame(0)]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"rightWrist\""))
    }

    // MARK: - 쓸 수 있는가

    @Test("버전이 다른 사이드카는 거부한다")
    func 버전_거부() {
        #expect(Self.sidecar(version: 999).isUsable(for: "clip-1.mov") == false)
        #expect(Self.sidecar().isUsable(for: "clip-1.mov"))
    }

    @Test("클립 이름이 다르면 거부한다")
    func 짝_불일치() {
        #expect(Self.sidecar().isUsable(for: "clip-2.mov") == false)
    }

    @Test("fps가 0이거나 크기가 0이면 거부한다")
    func 값_불량() {
        #expect(Self.sidecar(frameRate: 0).isUsable(for: "clip-1.mov") == false)
        #expect(Self.sidecar(pixelWidth: 0).isUsable(for: "clip-1.mov") == false)
        #expect(Self.sidecar(pixelHeight: 0).isUsable(for: "clip-1.mov") == false)
    }

    @Test("종횡비는 픽셀 크기에서 나온다")
    func 종횡비() throws {
        let aspect = try #require(Self.sidecar().aspect)
        #expect(abs(aspect - 16.0 / 9.0) < 1e-9)
        #expect(Self.sidecar(pixelHeight: 0).aspect == nil)
    }

    // MARK: - 프레임 찾기

    @Test("가장 가까운 프레임을 준다")
    func 근접() throws {
        let step = 1.0 / 60
        let sidecar = Self.sidecar(frames: (0..<10).map { Self.frame(Double($0) * step) })
        let found = try #require(sidecar.frame(at: step * 3 + step * 0.2))
        #expect(abs(found.seconds - step * 3) < 1e-9)
    }

    /// 허용 범위보다 멀면 그 시각에는 **데이터가 없다.** 가장 가까운 것을
    /// 억지로 쓰면 영상과 어긋난 자세를 확신 있게 보여준다.
    @Test("허용 범위를 넘으면 nil이다")
    func 허용_범위() {
        let sidecar = Self.sidecar(frames: [Self.frame(0)])
        // 60fps면 허용은 0.75/60 = 0.0125초
        #expect(sidecar.frame(at: 0.012) != nil)
        #expect(sidecar.frame(at: 0.02) == nil)
        #expect(sidecar.frame(at: 0.5) == nil)
    }

    /// **한 프레임이 비어 있는 구간은 여전히 끊긴다.** 허용 범위를 3/4로
    /// 넓힌 것이 그 구분을 지우지 않는다는 것을 고정한다 — 지우면 사람을
    /// 못 찾은 프레임에서 직전 자세가 그대로 보인다.
    @Test("사람을 못 찾아 빈 프레임은 nil로 떨어진다")
    func 빈_프레임() {
        let step = 1.0 / 60
        // 0, 1, (2 없음), 3
        let sidecar = Self.sidecar(
            frames: [Self.frame(0), Self.frame(step), Self.frame(step * 3)]
        )
        #expect(sidecar.frame(at: step * 2) == nil)
        #expect(sidecar.frame(at: step * 3) != nil)
    }

    @Test("프레임이 없으면 nil이다")
    func 빈_사이드카() {
        #expect(Self.sidecar().frame(at: 0) == nil)
    }

    /// `nominalFrameRate`는 발열 강등·가변 프레임률에서 실제와 다르다
    /// (ADR-0005). 그 값으로 허용 범위를 정하면 타임라인에 틈이 생겨
    /// **오버레이가 깜빡인다.** 실측 간격을 담는다.
    @Test("간격은 실측 중앙값이다 — 선언된 fps가 아니다")
    func 실측_간격() {
        // fps는 120이라고 적혀 있지만 실제 간격은 1/30이다.
        let step = 1.0 / 30
        let sidecar = Self.sidecar(
            frameRate: 120,
            frames: (0..<5).map { Self.frame(Double($0) * step) }
        )
        #expect(abs(sidecar.frameSpacing - step) < 1e-9)
        // 선언된 120fps 기준이면 허용이 0.00625초라 여기서 nil이 됐다.
        #expect(sidecar.frame(at: step * 2 + 0.008) != nil)
    }

    /// 빈 구간 하나가 섞인 짧은 클립에서 **상위** 중앙값을 집으면 그 큰
    /// 값이 기준이 돼 빠진 프레임을 메워 버린다.
    @Test("빠진 구간이 간격 기준을 끌어올리지 않는다")
    func 간격_중앙값() {
        let step = 1.0 / 60
        // 간격 [step, 2*step]
        let sidecar = Self.sidecar(frames: [Self.frame(0), Self.frame(step), Self.frame(step * 3)])
        #expect(abs(sidecar.frameSpacing - step) < 1e-9)
        #expect(sidecar.frame(at: step * 2) == nil)
    }

    @Test("프레임이 하나면 선언된 fps로 떨어진다")
    func 간격_없음() {
        let sidecar = Self.sidecar(frameRate: 60, frames: [Self.frame(0)])
        #expect(sidecar.frameSpacing == 0)
        #expect(sidecar.frame(at: 0.012) != nil)
        #expect(sidecar.frame(at: 0.02) == nil)
    }
}

@Suite("굽는 경로의 방향 변환")
struct OverlayBakerOrientationTests {

    /// `preferredTransform` → Vision에 넘길 방향.
    ///
    /// ⚠️ **이 매핑이 실제 녹화 파일과 맞는지는 실기기에서만 확인된다.**
    /// 여기서 고정하는 것은 "네 변환이 서로 다른 방향으로 간다"와
    /// "모르는 변환은 추측하지 않는다"뿐이다 — 틀려도 이 테스트는 통과한다.
    @Test("90의 배수 네 가지가 서로 다른 방향으로 간다")
    func 네_방향() {
        #expect(OverlayBaker.orientation(from: .identity) == .up)
        #expect(OverlayBaker.orientation(from: CGAffineTransform(rotationAngle: .pi / 2)) == .right)
        #expect(OverlayBaker.orientation(from: CGAffineTransform(rotationAngle: .pi)) == .down)
        #expect(
            OverlayBaker.orientation(from: CGAffineTransform(rotationAngle: -.pi / 2)) == .left
        )
    }

    /// 추측해 돌리면 오버레이가 통째로 어긋나고 그 원인을 찾기 어렵다.
    @Test("모르는 변환은 up으로 둔다 — 추측해 돌리지 않는다")
    func 모르는_변환() {
        #expect(
            OverlayBaker.orientation(from: CGAffineTransform(rotationAngle: .pi / 4)) == .up
        )
        #expect(OverlayBaker.orientation(from: CGAffineTransform(scaleX: 2, y: 3)) == .up)
    }

    /// 이동 성분은 방향과 무관하다. 보고 판단하면 같은 회전이 다른 방향이 된다.
    @Test("이동 성분은 방향을 바꾸지 않는다")
    func 이동_무관() {
        let rotated = CGAffineTransform(rotationAngle: .pi / 2)
            .concatenating(CGAffineTransform(translationX: 1080, y: 0))
        #expect(OverlayBaker.orientation(from: rotated) == .right)
    }
}
