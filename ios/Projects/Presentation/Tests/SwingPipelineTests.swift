import CoreGraphics
import Domain
import Foundation
import Synchronization
import Testing
import TeniVision
@testable import Presentation

/// 저장 호출을 받아 두는 가짜 저장소.
private final class SpyRepository: SessionRepository, Sendable {
    private let saved = Mutex<[Session]>([])

    var sessions: [Session] { saved.withLock { $0 } }

    func save(_ session: Session) async throws { saved.withLock { $0.append(session) } }
    func load(id: UUID) async throws -> Session? { nil }
    func loadAll() async throws -> [Session] { sessions }
    func delete(id: UUID) async throws {}
}

/// 임팩트가 있는 스윙 하나를 만드는 포즈 시계열.
///
/// `SwingTriggerTests`가 쓰는 것과 **같은 기하**다 — 어깨 중점 (0.50, 0.60),
/// 엉덩이 중점 (0.50, 0.40)이라 몸통 축이 수직이고, 손목의 x가 0.50을 지날
/// 때 교차한다. 0.35초에 200°를 돌면 약 9.97 rad/s로 진입 임계(8.0)를 넘는다.
private func swingFrames(
    startingAt start: TimeInterval,
    fps: Double = 60
) -> [PoseFrame] {
    let sweep = 200.0
    let seconds = 0.35
    let steps = Int((seconds * fps).rounded())
    let radius = 0.18
    let shoulderWidth = 0.10

    return (0..<steps).map { step in
        let degrees = sweep * Double(step) / Double(steps - 1)
        let radians = degrees * .pi / 180
        func sample(_ x: Double, _ y: Double) -> PoseJointSample {
            PoseJointSample(point: CGPoint(x: x, y: y), confidence: 0.9)
        }
        return PoseFrame(
            timestamp: start + Double(step) / fps,
            joints: [
                .leftShoulder: sample(0.50 - shoulderWidth / 2, 0.60),
                .rightShoulder: sample(0.50 + shoulderWidth / 2, 0.60),
                .leftHip: sample(0.46, 0.40),
                .rightHip: sample(0.54, 0.40),
                .rightWrist: sample(
                    0.50 + radius * cos(radians),
                    0.60 + radius * sin(radians)
                ),
            ]
        )
    }
}

@Suite("스윙 배선")
struct SwingPipelineTests {

    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "swing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("주 사용 손이 라켓 쪽으로 옮겨진다")
    func 손_변환() {
        #expect(Handedness.right.racketSide == .right)
        #expect(Handedness.left.racketSide == .left)
    }

    @Test("녹화를 시작하지 않으면 프레임을 받아도 아무것도 쌓지 않는다")
    func 녹화_전() async throws {
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: SpyRepository())
        )
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        #expect(await pipeline.clipCount == 0)
        #expect(await pipeline.isRecording == false)
    }

    @Test("스윙 하나를 흘리면 클립이 생기고 세션에 담긴다")
    func 클립_생성() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let startedAt = Date()
        await pipeline.begin(
            at: startedAt, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )

        // 스윙 + postRoll을 채울 만큼의 뒤 프레임.
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        for step in 0..<120 {
            let t = 0.4 + Double(step) / 60
            await pipeline.handle(try makeReadyFrame(seconds: t), pose: nil)
        }

        let session = await pipeline.end(at: startedAt.addingTimeInterval(3))
        #expect(await pipeline.failure == nil)

        let stored = try #require(repository.sessions.first)
        #expect(stored.id == session?.id)
        #expect(stored.clips.isEmpty == false)
        #expect(stored.clips.allSatisfy { $0.swings.isEmpty == false })
    }

    /// 원점을 빼지 않으면 부팅 이후 호스트 시각이 그대로 더해져, 부팅 후
    /// 11시간 된 기기에서 클립이 11시간 뒤로 기록된다(#91 리뷰 CRITICAL).
    @Test("클립 시각이 세션 시작 기준이다 — 부팅 시각이 새지 않는다")
    func 시계_원점() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let startedAt = Date()
        await pipeline.begin(
            at: startedAt, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )

        // 부팅 후 11시간 지난 기기의 PTS를 흉내낸다.
        let origin: TimeInterval = 11 * 3600
        for frame in swingFrames(startingAt: origin) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        for step in 0..<120 {
            let t = origin + 0.4 + Double(step) / 60
            await pipeline.handle(try makeReadyFrame(seconds: t), pose: nil)
        }
        _ = await pipeline.end(at: startedAt.addingTimeInterval(3))

        let clip = try #require(repository.sessions.first?.clips.first)
        let elapsed = clip.recordedAt.timeIntervalSince(startedAt)
        // 세션이 3초짜리였으므로 클립은 그 안에 있어야 한다.
        #expect(elapsed >= 0)
        #expect(elapsed < 10)
    }

    @Test("스윙이 0개여도 세션을 저장한다 — 0개도 결과다")
    func 빈_세션() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let startedAt = Date()
        await pipeline.begin(
            at: startedAt, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        // 사람이 없는 프레임만 흘린다.
        for step in 0..<30 {
            await pipeline.handle(try makeReadyFrame(seconds: Double(step) / 60), pose: nil)
        }
        _ = await pipeline.end(at: startedAt.addingTimeInterval(1))

        let stored = try #require(repository.sessions.first)
        #expect(stored.clips.isEmpty)
    }

    @Test("프레임이 한 장도 오지 않았으면 세션을 만들지 않는다")
    func 프레임_없음() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        #expect(await pipeline.end(at: Date()) == nil)
        #expect(repository.sessions.isEmpty)
    }

    @Test("저장소가 없으면 클립도 세션도 만들지 않는다")
    func 저장소_없음() async throws {
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(failure: "열 수 없다")
        )
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        #expect(await pipeline.clipCount == 0)
        #expect(await pipeline.end(at: Date()) == nil)
    }

    @Test("녹화를 두 번 시작해도 세션은 하나다")
    func 중복_시작() async throws {
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: SpyRepository())
        )
        let first = Date()
        await pipeline.begin(
            at: first, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        await pipeline.begin(
            at: first.addingTimeInterval(5), handedness: .left,
            situation: .match, observable: .swing, fps: 120
        )
        #expect(await pipeline.isRecording)
    }

    @Test("파일명 접두사는 시각에서 결정론적으로 나온다")
    func 접두사() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SwingPipeline.stamp(for: date) == SwingPipeline.stamp(for: date))
        #expect(SwingPipeline.stamp(for: date).count == 15)
    }
}
