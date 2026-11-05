import Foundation

/// 레코드에 없는 **고아 클립**을 찾는 쪽.
///
/// ## 왜 추상인가
///
/// 찾는 일에는 두 가지가 필요하다 — `Documents` 디렉터리 스캔과 `.mov`
/// 트랙의 fps 읽기(`AVFoundation`). 둘 다 `Domain`에 넣을 수 없다:
/// [아키텍처 2.2](../../../../../docs/02-설계/ARCHITECTURE.md)가 이 계층을
/// **"순수 Swift, 의존성 0"**으로 정했고, 앱 컨테이너 경로를 아는 것은
/// `ClipFileStore`를 추상으로 둔 이유와 같은 문제다.
///
/// 구현은 `Presentation`의 `DocumentsOrphanClipStore`다.
///
/// ## 어떻게 찾는가
///
/// 파일명 접두사가 **이미 세션 id 역할을 한다.** `SwingPipeline.open(at:)`이
/// `ClipRecorder`의 `stamp`와 `SessionBuilder`의 `startedAt`을 같은
/// `pending.startedAt`에서 만들기 때문이다. 레코드의 `startedAt`을 같은
/// 포맷으로 옮기면 그 세션의 파일명 접두사가 **기계적으로** 나온다.
///
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 2
public protocol OrphanClipStore: Sendable {
    /// 그 세션의 고아 클립. **`index` 오름차순**으로 준다.
    ///
    /// 레코드에 이미 담긴 클립은 제외한다 — 이 메서드가 주는 것은
    /// "디스크에 있는데 레코드가 모르는 것"뿐이다.
    func orphans(for session: Session) async -> [OrphanClip]
}

/// 디스크에서 찾은 클립 하나. 아직 `Clip`이 아니다 — 세션에 붙기 전이다.
public struct OrphanClip: Equatable, Sendable {
    public let fileName: String
    /// 파일명의 `index`. **정렬의 근거다** — 파일시스템 시각은 같은 초에
    /// 묶일 수 있어 순서를 보장하지 않는다.
    public let index: Int
    /// 파일 생성 시각. 녹화가 **시작된** 순간이다.
    ///
    /// ⚠️ 정상 경로의 `Clip.recordedAt`은 `세션 시작 + 프레임 시계 경과`다
    /// (`SessionBuilder.clip(from:…)`). 이 값은 파일시스템 시계라 **같은
    /// 뜻을 가리키지만 값이 수십~수백 ms 다를 수 있다.** 스윙 구간이 없는
    /// 세션이므로 그 차이가 분석에 쓰이지 않는다.
    public let recordedAt: Date
    /// `.mov` 트랙에서 읽은 실제 fps.
    ///
    /// 세션의 `fps`를 그대로 쓰면 발열 강등을 걸친 세션에서 강등 후
    /// 클립이 120fps로 기록되고, 분석이 프레임 간격을 잘못 가정한다 —
    /// [ADR-0005](../../../../../docs/05-결정/adr/ADR-0005-thermal-auto-adjust.md).
    public let fps: Int

    public init(fileName: String, index: Int, recordedAt: Date, fps: Int) {
        self.fileName = fileName
        self.index = index
        self.recordedAt = recordedAt
        self.fps = fps
    }
}

/// 끝나지 않은 세션을 닫고 고아 클립을 붙인다.
///
/// ## 스윙 구간은 비운다
///
/// 고아 클립에는 오버레이 사이드카가 없다 — [#121](https://github.com/wnsgur9137/TeniTeni/issues/121)의
/// `OverlayBakeQueue`는 **리플레이를 열 때** 굽기 때문이다. 재분석하려면
/// `AVAssetReader` 한 패스와 포즈 추정을 새로 배선해야 하고 그것은 이
/// 작업이 아니다.
///
/// 대신 `recoveredAt`을 남긴다. 그것이 없으면 스윙 0개가 "못 찾았다"로
/// 읽혀 진단 화면이 삼각대를 확인하라고 한다.
///
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 4
public struct RecoverSessionUseCase: Sendable {

    /// 복구 결과.
    public enum Outcome: Equatable, Sendable {
        /// 클립 n개를 붙여 세션을 닫았다.
        case recovered(Session)
        /// 디스크에 영상이 **하나도 없다.** 첫 프레임이 오기 전에 죽은
        /// 세션이다 — 복구할 것이 없으므로 화면은 폐기만 제안한다.
        case nothingToRecover
    }

    private let repository: any SessionRepository
    private let orphans: any OrphanClipStore

    public init(repository: any SessionRepository, orphans: any OrphanClipStore) {
        self.repository = repository
        self.orphans = orphans
    }

    /// - Parameter now: `recoveredAt`에 넣을 시각. 테스트가 고정값을 준다.
    ///
    /// `endedAt`은 **마지막 클립의 `recordedAt`**으로 둔다. 강제 종료
    /// 시각은 아무도 모르고, `now`를 쓰면 어제 죽은 세션의 `duration`이
    /// 하루가 된다 — 보관함과 세션 비교가 그 값을 읽는다.
    public func execute(_ session: Session, now: Date) async throws -> Outcome {
        // ★ **확인을 띄운 뒤 레코드가 바뀔 수 있다.** 들고 있던 스냅샷으로
        //   저장하면 그 사이의 변경을 덮는다 — 분석이 끝난 세션의
        //   `endedAt`과 스윙이 추정값으로 바뀐다. #126이 삭제에서 세운
        //   "확인 뒤 다시 찾는다"와 같은 이유다.
        let stored = try await repository.load(id: session.id)
        guard let current = stored else {
            // 레코드가 사라졌다. 사용자가 다른 경로로 지웠다는 뜻이므로
            // 되살리지 않는다.
            return .nothingToRecover
        }
        guard current.isUnfinished else {
            // 이미 닫힌 세션이다. 복구할 것이 없다 — 덮어쓰면 멀쩡한
            // `endedAt`을 추정값으로 바꾼다.
            return .recovered(current)
        }

        // 다른 세션이 아는 파일은 가져오지 않는다. 접두사는 **초 단위**라
        // 같은 초에 시작한 두 세션이 접두사를 공유할 수 있고, 그러면 한쪽의
        // 클립을 다른 쪽이 가져간다 — 원래 세션에서 조용히 사라진다.
        let taken = try await claimedFileNames(excluding: current.id)
        let found = await orphans.orphans(for: current)
            .filter { !taken.contains($0.fileName) }
        guard !found.isEmpty else { return .nothingToRecover }

        let clips = found
            .sorted { $0.index < $1.index }
            .map { orphan in
                Clip(
                    fileName: orphan.fileName,
                    recordedAt: orphan.recordedAt,
                    fps: orphan.fps,
                    swings: []
                )
            }

        var recovered = current
        recovered.clips += clips
        // 마지막 클립이 찍힌 시각. `now`가 아니다 — 위 주석을 보라.
        //
        // ⚠️ **`startedAt`을 하한으로 둔다.** 파일 시각은 파일시스템
        //   시계이고 세션 시작은 벽시계다. 기기 시각이 조정되면 클립이
        //   세션보다 이르게 찍혀 `duration`이 **음수**가 된다.
        let last = clips.map(\.recordedAt).max() ?? current.startedAt
        recovered.endedAt = max(current.startedAt, last)
        recovered.recoveredAt = now

        try await repository.save(recovered)
        return .recovered(recovered)
    }

    /// 다른 세션의 레코드가 이미 들고 있는 파일 이름.
    private func claimedFileNames(excluding id: UUID) async throws -> Set<String> {
        Set(
            try await repository.loadAll()
                .lazy
                .filter { $0.id != id }
                .flatMap { $0.clips.map(\.fileName) }
        )
    }
}

/// 끝나지 않은 세션을 폐기한다. **레코드와 파일 전부를 지운다.**
///
/// ## 왜 `DeleteSessionUseCase`를 쓸 수 없는가
///
/// 그쪽은 **레코드의 `clips`를 돌며** 파일을 지운다. 미완 세션의 레코드에는
/// 클립이 0개다 — 촬영 중에는 레코드를 갱신하지 않기 때문이다(그러면
/// 클립마다 그래프를 전부 다시 쓰고, 그것이 120fps 분석 중의 디스크
/// I/O다). 그대로 쓰면 레코드만 사라지고 **고아 `.mov`가 그대로 남는다.**
///
/// ## 순서는 #126과 같다
///
/// **파일 먼저, 레코드 나중에.** 레코드를 먼저 지우면 실패 시 보이지 않는
/// 고아 파일이 남고, 파일을 먼저 지우면 #120이 "영상이 없습니다"로
/// 보여주는 빈 레코드가 남는다. 보이지 않는 쓰레기보다 보이는 빈 껍데기가
/// 낫다.
///
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 5
public struct DiscardSessionUseCase: Sendable {

    /// 폐기 결과.
    public enum Outcome: Equatable, Sendable {
        case discarded
        /// ⚠️ **그 사이에 세션이 닫혔다.** 폐기하지 않았다 — 분석이 끝난
        /// 세션을 지우게 된다. 호출부가 다시 물어야 한다.
        case alreadyClosed
    }

    private let repository: any SessionRepository
    private let files: any ClipFileStore
    private let orphans: any OrphanClipStore

    public init(
        repository: any SessionRepository,
        files: any ClipFileStore,
        orphans: any OrphanClipStore
    ) {
        self.repository = repository
        self.files = files
        self.orphans = orphans
    }

    /// 지울 파일 수. **확인 문구가 이 값을 적는다.**
    ///
    /// `session.clips.count`를 쓰면 미완 세션에서 **항상 0**이다. #126이
    /// 확인 문구를 "절차가 아니라 확인"으로 만든 근거가 그 숫자인데,
    /// 0으로 뜨면 그 근거가 무너진다.
    public func clipCount(_ session: Session) async -> Int {
        await fileNames(session).count
    }

    @discardableResult
    public func execute(_ session: Session) async throws -> Outcome {
        // ★ **확인을 띄운 뒤 레코드가 바뀔 수 있다.** 닫힌 세션을 폐기하면
        //   분석이 끝난 스윙과 그 영상이 사라지고 되돌릴 수 없다.
        if let current = try await repository.load(id: session.id), !current.isUnfinished {
            return .alreadyClosed
        }

        // ★ 파일 먼저.
        for fileName in await fileNames(session) {
            await files.remove(fileName: fileName)
        }
        try await repository.delete(id: session.id)
        return .discarded
    }

    /// 레코드가 아는 것과 디스크에만 있는 것의 **합집합.** 둘 다 지운다 —
    /// 어느 한쪽만 보면 남는 것이 생긴다.
    private func fileNames(_ session: Session) async -> [String] {
        var names = session.clips.map(\.fileName)
        var seen = Set(names)
        // 다른 세션이 아는 파일은 **지우지 않는다.** 접두사가 초 단위라
        // 같은 초에 시작한 세션의 클립이 걸릴 수 있고, 그것을 지우면
        // 사용자가 폐기하지 않은 영상이 사라진다.
        let claimed = (try? await repository.loadAll())?
            .lazy
            .filter { $0.id != session.id }
            .flatMap { $0.clips.map(\.fileName) } ?? []
        seen.formUnion(claimed)

        for orphan in await orphans.orphans(for: session) where !seen.contains(orphan.fileName) {
            names.append(orphan.fileName)
            seen.insert(orphan.fileName)
        }
        return names
    }
}
