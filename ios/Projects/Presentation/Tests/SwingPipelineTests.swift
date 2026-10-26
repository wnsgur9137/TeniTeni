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

    /// 기획서 선택지 3: "촬영은 되지만 세션이 저장되지 않는다". 클립
    /// 파일조차 안 만들면 디스크에 복구할 자산이 남지 않는다.
    @Test("저장소가 없어도 클립은 쓰고 세션만 남기지 않는다")
    func 저장소_없음() async throws {
        let dir = try directory()
        let pipeline = SwingPipeline(directory: dir, storage: SessionStorage(failure: "열 수 없다"))
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        _ = await pipeline.end(at: Date())

        // 트리거는 돌았고 파일도 생겼다. 세션만 없다.
        #expect(await pipeline.swingCount > 0)
        #expect(await pipeline.clipCount == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasSuffix(".mov") })
    }

    /// `#expect(isRecording)`만 보면 guard를 지워도 통과한다 — `pending`이
    /// 덮일 뿐 `isRecording`은 여전히 참이기 때문이다. 두 번째 `begin`의
    /// 인자가 **반영되지 않았음**을 저장된 세션으로 확인한다.
    @Test("녹화를 두 번 시작해도 첫 번째 설정이 유지된다")
    func 중복_시작() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let first = Date()
        await pipeline.begin(
            at: first, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        await pipeline.begin(
            at: first.addingTimeInterval(5), handedness: .left,
            situation: .match, observable: .lineCall, fps: 120
        )
        await pipeline.handle(try makeReadyFrame(seconds: 0), pose: nil)
        _ = await pipeline.end(at: first.addingTimeInterval(1))

        let stored = try #require(repository.sessions.first)
        #expect(stored.fps == 60)
        #expect(stored.situation == .rally)
        #expect(stored.observable == .swing)
    }

    @Test("파일명 접두사가 시각에서 결정론적으로 나온다")
    func 접두사() {
        // UTC로 고정했으므로 기대값을 적을 수 있다. 동어반복(같은 입력 →
        // 같은 출력)은 포매팅이 틀려도 통과한다.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(SwingPipeline.stamp(for: date) == "20231114-221320")
    }

    // MARK: - 리뷰가 비어 있다고 지적한 자리

    /// 재발화 간격(0.8초)이 구간(4초)보다 짧아 연속 스윙은 거의 항상 겹친다.
    /// 병합이 풀리면 클립이 둘로 쪼개진다.
    @Test("겹치는 스윙 둘은 클립 하나로 병합된다")
    func 겹침_병합() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let startedAt = Date()
        await pipeline.begin(
            at: startedAt, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )

        // 두 스윙을 1초 간격으로. 구간(±2초)이 겹친다.
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        for frame in swingFrames(startingAt: 1.0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        // postRoll을 채워 구간을 닫는다.
        for step in 0..<180 {
            await pipeline.handle(try makeReadyFrame(seconds: 1.4 + Double(step) / 60), pose: nil)
        }
        _ = await pipeline.end(at: startedAt.addingTimeInterval(5))

        let stored = try #require(repository.sessions.first)
        #expect(stored.clips.count == 1, "겹치는 후보는 한 클립으로 묶인다")
        let clip = try #require(stored.clips.first)
        #expect(clip.swings.count == 2, "병합돼도 스윙은 둘 다 기록된다")
    }

    /// `클립_생성`은 postRoll을 채워 `advance`로 닫으므로 `finish()` 플러시
    /// 경로를 지나지 않는다. 마지막 스윙을 버리지 않는지는 여기서 본다.
    @Test("postRoll을 못 채운 마지막 스윙도 저장된다")
    func 마지막_스윙() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let startedAt = Date()
        await pipeline.begin(
            at: startedAt, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        // 스윙만 흘리고 **바로** 멈춘다. postRoll 2초를 채우지 않는다.
        for frame in swingFrames(startingAt: 0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        _ = await pipeline.end(at: startedAt.addingTimeInterval(1))

        let stored = try #require(repository.sessions.first)
        #expect(stored.clips.isEmpty == false, "가진 만큼이라도 저장한다")
    }

    /// 세대 토큰이 없으면 `handle`의 뒤늦은 쓰기가 닫힌 세션을 되살리고,
    /// 그 뒤 모든 녹화가 첫 세션 id로 덮여 레코드가 사라진다.
    @Test("세션을 닫은 뒤 들어온 프레임이 세션을 되살리지 않는다")
    func 재진입() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        await pipeline.handle(try makeReadyFrame(seconds: 0), pose: nil)
        _ = await pipeline.end(at: Date())
        #expect(await pipeline.isRecording == false)

        // 닫힌 뒤에 프레임이 더 들어온다.
        for frame in swingFrames(startingAt: 1.0) {
            await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        #expect(await pipeline.isRecording == false, "닫힌 세션이 되살아나면 다음 녹화가 영구히 막힌다")

        // 두 번째 녹화가 정상적으로 열린다.
        let second = Date()
        await pipeline.begin(
            at: second, handedness: .left, situation: .match, observable: .lineCall, fps: 120
        )
        await pipeline.handle(try makeReadyFrame(seconds: 2.0), pose: nil)
        _ = await pipeline.end(at: second.addingTimeInterval(1))
        #expect(repository.sessions.count == 2, "두 세션이 각자 남는다")
        #expect(Set(repository.sessions.map(\.id)).count == 2, "같은 id로 덮이면 하나가 사라진다")
    }

    /// `handle`이 `await` 지점에 멈춰 있는 동안 `end()`가 들어오는 경로.
    /// actor가 비는 그 틈이 C2의 실패 지점이었다.
    ///
    /// **단정은 불변식만 본다.** 어느 쪽이 먼저 도느냐는 보장되지 않으므로,
    /// "닫은 뒤에는 닫혀 있고 다음 녹화가 정상적으로 열린다"를 확인한다.
    @Test("handle이 멈춘 사이에 end가 들어와도 세션이 잠기지 않는다")
    func 교차_종료() async throws {
        let repository = SpyRepository()
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: repository)
        )
        let first = Date()
        await pipeline.begin(
            at: first, handedness: .right, situation: .rally, observable: .swing, fps: 60
        )

        let frames = swingFrames(startingAt: 0)
        let ready = try frames.map { try makeReadyFrame(seconds: $0.timestamp) }
        // 프레임을 흘리는 Task와 닫는 호출을 겹친다.
        let feeding = Task {
            for (frame, pose) in zip(ready, frames) {
                await pipeline.handle(frame, pose: pose)
            }
        }
        _ = await pipeline.end(at: first.addingTimeInterval(1))
        await feeding.value

        #expect(await pipeline.isRecording == false, "닫힌 뒤에 열린 채로 남으면 다음 녹화가 막힌다")

        let second = first.addingTimeInterval(10)
        await pipeline.begin(
            at: second, handedness: .left, situation: .match, observable: .lineCall, fps: 120
        )
        await pipeline.handle(try makeReadyFrame(seconds: 100), pose: nil)
        _ = await pipeline.end(at: second.addingTimeInterval(1))

        #expect(Set(repository.sessions.map(\.id)).count == repository.sessions.count,
                "같은 id로 덮이면 레코드가 사라진다")
        #expect(repository.sessions.contains { $0.fps == 120 }, "두 번째 세션이 자기 설정으로 남는다")
    }

    /// 소급분이 캡처 풀을 붙들므로 상한이 없으면 풀이 고갈돼 분석이
    /// 끊긴다. 상한에 걸려 버린 장 수가 **보여야** 한다 — 조용히 짧아지면
    /// 클립의 머리가 왜 없는지 알 수 없다.
    @Test("소급분이 상한을 넘기면 세면서 버린다")
    func 소급_상한() async throws {
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: SpyRepository())
        )
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        // 상한(24장)보다 훨씬 많이 흘린다. 스윙은 없으므로 전부 소급분이다.
        for step in 0..<100 {
            await pipeline.handle(try makeReadyFrame(seconds: Double(step) / 60), pose: nil)
        }
        // 클립이 닫혀야 수치가 올라온다 — 스윙이 없으니 end로 확인한다.
        _ = await pipeline.end(at: Date())
        #expect(await pipeline.droppedBacklog > 0, "상한을 넘긴 만큼 세어야 한다")
    }

    /// 벽치기는 기본값으로는 통째로 놓친다 — 벽이 가까워 스윙이 짧고 느리다.
    @Test("상황이 트리거 프로파일을 고른다")
    func 상황별_프로파일() {
        #expect(CaptureSituation.wall.triggerProfile.enterAngularVelocity
            == SwingTriggerProfile.wall.enterAngularVelocity)
        #expect(CaptureSituation.rally.triggerProfile.enterAngularVelocity
            == SwingTriggerProfile.default.enterAngularVelocity)
    }

    /// 클립은 구간이 닫힐 때야 저장된다. 그 값을 띄우면 랠리 중에는 0이 뜬다.
    @Test("스윙 수는 트리거가 울리는 즉시 올라간다")
    func 즉시_카운트() async throws {
        let pipeline = SwingPipeline(
            directory: try directory(), storage: SessionStorage(repository: SpyRepository())
        )
        await pipeline.begin(
            at: Date(), handedness: .right, situation: .rally, observable: .swing, fps: 60
        )
        var last = SwingSnapshot(
            swingCount: 0, clipCount: 0, failure: nil, droppedBacklog: 0, seconds: 0
        )
        for frame in swingFrames(startingAt: 0) {
            last = await pipeline.handle(try makeReadyFrame(seconds: frame.timestamp), pose: frame)
        }
        // 아직 postRoll을 못 채웠으니 클립은 0인데 스윙은 세어져 있다.
        #expect(last.swingCount == 1)
        #expect(last.clipCount == 0)
    }
}
