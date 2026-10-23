import Domain
import Foundation
import Testing
import TeniVision
@testable import Presentation

private actor SpyRepository: SessionRepository {
    private(set) var saved: [Session] = []

    func save(_ session: Session) async throws {
        saved.removeAll { $0.id == session.id }
        saved.append(session)
    }

    func load(id: UUID) async throws -> Session? { saved.first { $0.id == id } }
    func loadAll() async throws -> [Session] { saved }
    func delete(id: UUID) async throws { saved.removeAll { $0.id == id } }
}

private let start = Date(timeIntervalSince1970: 1_000_000)

private func recorded(
    name: String = "s-1.mov",
    startedAt: TimeInterval = 1.0,
    duration: TimeInterval = 4.0,
    swings: [RecordedSwing] = [
        RecordedSwing(
            startSeconds: 0.0, impactSeconds: 2.0, endSeconds: 4.0, peakAngularVelocity: 12.0
        )
    ]
) -> RecordedClip {
    RecordedClip(
        url: URL(filePath: "/tmp/clips/\(name)"),
        startedAt: startedAt,
        duration: duration,
        frameCount: 121,
        swings: swings
    )
}

private func builder(_ repository: any SessionRepository) -> SessionBuilder {
    SessionBuilder(
        startedAt: start, situation: .ballMachine, observable: .swing, fps: 120,
        repository: repository
    )
}

@Suite("세션 조립")
struct SessionBuilderTests {

    @Test("클립을 넣고 끝내면 저장된다")
    func 저장() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(recorded())

        let session = try await subject.finish(at: start.addingTimeInterval(60))
        let saved = await repository.saved

        #expect(saved.count == 1)
        #expect(saved.first?.id == session.id)
        #expect(session.clips.count == 1)
        #expect(session.swingCount == 1)
        #expect(session.fps == 120)
        #expect(session.situation == .ballMachine)
    }

    @Test("파일명만 담는다 — 디렉터리는 버린다")
    func 파일명() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(recorded(name: "20261023-101500-1.mov"))
        let session = try await subject.finish(at: start)

        #expect(session.clips.first?.fileName == "20261023-101500-1.mov")
    }

    @Test("클립 시각은 세션 시작에 상대초를 더한 것이다")
    func 시각() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(recorded(startedAt: 12.5))
        let session = try await subject.finish(at: start)

        #expect(session.clips.first?.recordedAt == start.addingTimeInterval(12.5))
    }

    @Test("스윙의 상대초가 자리를 바꾸지 않고 옮겨진다")
    func 스윙_매핑() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(
            recorded(swings: [
                RecordedSwing(
                    startSeconds: 0.25, impactSeconds: 1.75, endSeconds: 3.5,
                    peakAngularVelocity: 9.0
                )
            ])
        )
        let session = try await subject.finish(at: start)
        let swing = try #require(session.clips.first?.swings.first)

        #expect(swing.startSeconds == 0.25)
        #expect(swing.impactSeconds == 1.75)
        #expect(swing.endSeconds == 3.5)
        #expect(swing.kind == nil)
    }

    @Test("스윙이 하나도 없어도 세션은 저장된다")
    func 스윙_0개() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        let session = try await subject.finish(at: start.addingTimeInterval(30))
        let saved = await repository.saved

        #expect(saved.count == 1)
        #expect(session.clips.isEmpty)
        #expect(session.swingCount == 0)
        #expect(session.duration == 30)
    }

    @Test("클립 여럿이 넣은 순서대로 쌓인다")
    func 여러_클립() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(recorded(name: "s-1.mov", startedAt: 1))
        await subject.add(recorded(name: "s-2.mov", startedAt: 9))
        #expect(await subject.clipCount == 2)

        let session = try await subject.finish(at: start)
        #expect(session.clips.map(\.fileName) == ["s-1.mov", "s-2.mov"])
    }

    @Test("저장한 세션을 다시 읽으면 같다")
    func 왕복() async throws {
        let repository = SpyRepository()
        let subject = builder(repository)
        await subject.add(recorded())
        let session = try await subject.finish(at: start.addingTimeInterval(10))

        let loaded = try await repository.load(id: session.id)
        #expect(loaded == session)
    }
}
