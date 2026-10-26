import Domain
import Foundation

/// 저장소가 주입되지 않았을 때 쓰는 기본값.
///
/// ## 왜 조용히 비어 있지 않고 던지는가
///
/// 빈 배열을 돌려주면 화면은 "기록이 없다"를 그린다. 그런데 사실은
/// **배선이 빠진 것**이고, 사용자는 찍은 것이 사라졌다고 읽는다. 던지면
/// 화면이 사유를 띄우고 그 자리에서 드러난다.
///
/// `SwiftDataSessionRepository`는 `Data`에 있고 `Presentation`은 그것을
/// 모른다. 조립은 `Application`이 한다 — [아키텍처 2.2](../../../../../docs/02-설계/ARCHITECTURE.md).
///
/// 근거: docs/07-기획/SPEC-0110-session-summary.md
public struct UnavailableSessionRepository: SessionRepository {

    struct NotWired: LocalizedError {
        var errorDescription: String? { "세션 저장소가 연결되지 않았습니다" }
    }

    public init() {}

    public func save(_ session: Session) async throws { throw NotWired() }
    public func load(id: UUID) async throws -> Session? { throw NotWired() }
    public func loadAll() async throws -> [Session] { throw NotWired() }
    public func delete(id: UUID) async throws { throw NotWired() }
}
