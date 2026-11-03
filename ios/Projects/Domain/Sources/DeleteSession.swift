import Foundation

/// 클립의 **파일**을 지우는 쪽.
///
/// ## 왜 추상인가
///
/// 저장소가 파일까지 지우면 `Data`가 `Documents` 경로 규칙과 오버레이
/// 사이드카 이름 규칙을 알게 된다. 그 규칙은 이미 `Presentation`에
/// 있으므로(`ClipLocator`·`OverlaySidecarStore`) **두 곳에 생기고, 둘이
/// 어긋날 수 있다.**
///
/// ## 왜 던지지 않는가
///
/// 파일이 **이미 없는 것은 실패가 아니다** — 사용자가 파일 앱에서 지웠거나
/// iOS가 정리했을 수 있다(#120). 던지면 호출부가 "없어서 못 지웠다"와
/// "있는데 못 지웠다"를 구분해야 하는데 **둘 다 결과가 같다**: 그 파일은
/// 이제 없다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 1
public protocol ClipFileStore: Sendable {
    /// 그 클립의 영상과 **딸린 것 전부**(오버레이 사이드카 등)를 지운다.
    func remove(fileName: String) async
}

/// 세션 하나를 통째로 지운다.
///
/// ## 순서가 "남는 상태"를 정한다
///
/// **파일을 먼저 지운다.** 어느 쪽이 먼저냐가 실패했을 때 남는 것을 정한다.
///
/// | 순서 | 실패하면 남는 것 | 성질 |
/// |---|---|---|
/// | 레코드 먼저 | 고아 `.mov` | **보이지 않는다.** 공간만 먹는다 |
/// | **파일 먼저** | 파일 없는 레코드 | #120이 "영상이 없습니다"로 **보여준다** |
///
/// 보이지 않는 쓰레기보다 **보이는 빈 껍데기**가 낫다 — 후자는 사용자가
/// 스스로 치울 수 있고, 전자는 알 수조차 없다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 2
public struct DeleteSessionUseCase: Sendable {

    private let repository: any SessionRepository
    private let files: any ClipFileStore

    public init(repository: any SessionRepository, files: any ClipFileStore) {
        self.repository = repository
        self.files = files
    }

    /// 세션의 클립 파일 전부를 지우고, 그다음 레코드를 지운다.
    ///
    /// - Throws: 레코드 삭제 실패. **파일은 이미 지워진 상태다** —
    ///   되돌리지 않는다. 되돌리려면 지운 파일을 복원해야 하는데 우리는
    ///   그것을 들고 있지 않다.
    public func execute(_ session: Session) async throws {
        for clip in session.clips {
            await files.remove(fileName: clip.fileName)
        }
        try await repository.delete(id: session.id)
    }
}

/// 클립 하나를 지운다. **마지막 클립이면 세션도 지운다.**
///
/// ## 왜 세션까지 지우는가
///
/// 빈 세션을 남기면 보관함에 #120이 만든 "영상이 없습니다" 행이 뜨고,
/// **그 행이 뜨는 이유가 둘이 된다** — 파일이 사라졌거나, 내가 지웠거나.
/// 구분하려면 레코드에 "지운 것"을 적어야 하고, 그러면 필드와 화면 상태가
/// 하나씩 더 늘어난다.
///
/// 지워지면 그 행이 없다. 모호함도 없다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 4
public struct DeleteClipUseCase: Sendable {

    /// 지운 결과. 화면이 다음에 무엇을 할지 정한다.
    public enum Outcome: Equatable, Sendable {
        /// 클립만 지웠다. 세션은 남아 있다.
        case clipRemoved
        /// 마지막 클립이었으므로 세션도 지웠다.
        case sessionRemoved
    }

    private let repository: any SessionRepository
    private let files: any ClipFileStore

    public init(repository: any SessionRepository, files: any ClipFileStore) {
        self.repository = repository
        self.files = files
    }

    public func execute(_ session: Session, clipID: UUID) async throws -> Outcome {
        guard let clip = session.clips.first(where: { $0.id == clipID }) else {
            // 없는 클립을 지우라는 요청. 이미 지워졌을 수 있다 — 실패로
            // 보지 않는다. 결과는 같다: 그 클립은 없다.
            return session.clips.isEmpty ? .sessionRemoved : .clipRemoved
        }

        // ★ 파일 먼저. 위 표를 보라.
        await files.remove(fileName: clip.fileName)

        let remaining = session.clips.filter { $0.id != clipID }
        guard !remaining.isEmpty else {
            try await repository.delete(id: session.id)
            return .sessionRemoved
        }

        // 남은 클립으로 세션을 다시 쓴다. `save`가 덮어쓴다 —
        // `clips`가 `var`이므로 새 타입을 만들지 않는다.
        var updated = session
        updated.clips = remaining
        try await repository.save(updated)
        return .clipRemoved
    }
}
