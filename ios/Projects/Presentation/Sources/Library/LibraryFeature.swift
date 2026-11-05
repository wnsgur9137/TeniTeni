import ComposableArchitecture
import Domain
import Foundation

/// 보관함 — 과거 세션 목록.
///
/// ## 왜 목록이 요약을 직접 띄우지 않는가
///
/// D-03이 "`Presentation` 내 Feature 간 직접 의존 금지, `Application`
/// 코디네이터 경유"를 정했다. 여기는 `.delegate(.sessionTapped(id))`만
/// 올리고, 요약을 여는 것은 `AppFeature`가 한다.
///
/// ## 왜 세션을 들고 넘기지 않는가
///
/// 요약은 **`id`만 받아 스스로 읽는다**([SPEC-0110](../../../../../docs/07-기획/SPEC-0110-session-summary.md)).
/// 세션을 통째로 넘기면 촬영 직후와 보관함이 다른 코드가 되고, 저장이
/// 실제로 됐는지도 영원히 모른다. 두 번 읽는 비용은 조회 한 건이고,
/// 입구가 둘로 갈리는 비용은 영구적이다.
///
/// ## 왜 빈 목록과 읽기 실패를 구분하는가
///
/// 레퍼런스 조사에서 반복된 불만은 "찾기 어렵다"가 아니라 **"사라졌다"**다
/// ([SwingVision](../../../../../docs/08-레퍼런스/SwingVision.md) 2026-10-27절).
/// 읽기 실패를 빈 목록으로 보여주면 그것이 바로 "사라졌다"로 읽힌다.
///
/// 근거: docs/07-기획/SPEC-0116-session-library.md
@Reducer
public struct LibraryFeature {

    @ObservableState
    public struct State: Equatable {
        public var phase: Phase
        /// 세션별 클립 파일 결손. **레코드가 아니라 지금 사실이다** —
        /// 목록을 다시 읽을 때마다 새로 확인한다(SPEC-0120 선택지 4).
        ///
        /// 키가 없으면 아직 확인하지 않았다는 뜻이다. 목록은 **확인 전에
        /// 먼저 그려진다** — 읽기가 느려도 멈추지 않는다.
        public var availability: [UUID: ClipAvailability]
        /// 확인을 기다리는 삭제. **되돌리기가 없으므로 이 다이얼로그가
        /// 유일한 안전장치다**(SPEC-0126 선택지 3).
        @Presents public var deleting: DeleteTarget?
        /// 끝나지 않은 세션의 복구 / 폐기 시트.
        ///
        /// **모달이 아니라 행에서 올라온다.** 앱 시작 즉시 묻지 않는
        /// 이유는 IA-FLOW 10.6에 적었다 — 사용자가 요청하지 않은 결정을
        /// 강요하고, 미루면 매 실행 뜬다.
        @Presents public var recovering: RecoverTarget?
        /// 지우다 실패했다. 사유를 보여준다 — 조용히 넘기면 사용자는
        /// 지워진 줄 안다.
        ///
        /// **복구·폐기 실패도 여기 적는다.** 배너를 따로 두면 같은 자리에
        /// 둘이 겹칠 수 있다.
        public var deleteFailure: String?

        public init(
            phase: Phase = .loading,
            availability: [UUID: ClipAvailability] = [:],
            deleting: DeleteTarget? = nil,
            recovering: RecoverTarget? = nil,
            deleteFailure: String? = nil
        ) {
            self.phase = phase
            self.availability = availability
            self.deleting = deleting
            self.recovering = recovering
            self.deleteFailure = deleteFailure
        }

        /// 그 세션의 결손. 확인 전이면 `nil`이다.
        public func availability(for sessionID: UUID) -> ClipAvailability? {
            availability[sessionID]
        }

        /// 비어 있는가. **읽기 실패는 비어 있는 것이 아니다.**
        public var isEmpty: Bool {
            guard case .loaded(let sessions) = phase else { return false }
            return sessions.isEmpty
        }
    }

    public enum Phase: Equatable, Sendable {
        case loading
        case loaded([Session])
        /// 읽지 못했다. **사유를 보여준다.**
        case failed(String)
    }

    public enum Action: Equatable {
        /// 탭이 떴거나, 탭으로 **되돌아왔다.** 두 경로 모두 다시 읽는다 —
        /// 촬영하고 돌아왔을 때 방금 세션이 없는 것이 이 화면의 최악 실패다.
        case appeared
        case loaded([Session])
        /// 클립 파일 확인이 끝났다. 목록이 그려진 **뒤에** 온다.
        case availabilityChecked([UUID: ClipAvailability])
        case failed(String)
        case retryTapped
        case sessionTapped(UUID)

        /// 행을 스와이프해 삭제를 눌렀다. **아직 지우지 않는다.**
        case deleteRequested(UUID)
        case deleteConfirmed
        case deleteCancelled
        case deleteFinished(Result<UUID, DeleteError>)
        case deleteFailureDismissed

        /// 끝나지 않은 세션 행을 눌렀다. 요약이 아니라 **시트**를 띄운다.
        case recoverRequested(UUID)
        /// 디스크 스캔이 끝났다. 시트가 그려진 **뒤에** 온다.
        case orphansCounted(UUID, Int)
        case recoverConfirmed
        case discardConfirmed
        case recoverDismissed
        /// 복구 결과. 성공하면 목록을 다시 읽는다 — 그 세션의 클립 수와
        /// 스윙 수가 바뀌었다.
        case recoverFinished(Result<UUID, DeleteError>)
        case discardFinished(Result<UUID, DeleteError>)
        /// 폐기를 **하지 않았다.** 확인하는 사이에 세션이 닫혔다 —
        /// 분석이 끝난 세션을 지우면 되돌릴 수 없다.
        case discardSkipped

        /// 빈 상태의 "촬영하러 가기".
        case captureTapped
        case delegate(Delegate)

        /// 삭제 실패. `Error`는 `Equatable`이 아니므로 사유만 옮긴다 —
        /// 액션이 `Equatable`이어야 `TestStore`가 비교한다.
        public struct DeleteError: Error, Equatable {
            public let reason: String
            public init(reason: String) { self.reason = reason }
        }

        public enum Delegate: Equatable {
            case sessionTapped(UUID)
            /// 빈 상태에서 촬영 탭으로 보낸다. "없다"만 말하고 끝내면
            /// 사용자는 다음에 무엇을 할지 모른다.
            case goToCapture
        }
    }

    private let repository: any SessionRepository
    private let locator: ClipLocator
    private let files: any ClipFileStore
    private let orphans: any OrphanClipStore
    /// `recoveredAt`에 넣을 시각. 테스트가 고정값을 준다.
    private let now: @Sendable () -> Date

    public init(
        repository: any SessionRepository,
        locator: ClipLocator = ClipLocator(),
        files: any ClipFileStore = DocumentsClipFileStore(),
        orphans: any OrphanClipStore = DocumentsOrphanClipStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.locator = locator
        self.files = files
        self.orphans = orphans
        self.now = now
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared, .retryTapped:
                state.phase = .loading
                // 지난 확인 결과를 버린다. 그 사이에 파일이 지워졌을 수
                // 있고, 그것이 이 확인의 존재 이유다.
                state.availability = [:]
                // `self`를 포획하면 Reducer가 Sendable이 아니어서 막힌다.
                let repository = repository
                return .run { send in
                    do {
                        await send(.loaded(try await repository.loadAll()))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .loaded(let sessions):
                // **여기서 정렬한다.** `loadAll()`이 "최근 것부터"를 약속하지만
                // 그 약속에 기대면 순서가 바뀌는 날 조용히 깨진다 — 화면은
                // 아무 오류도 내지 않고 뒤섞인 목록을 보여준다.
                let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
                state.phase = .loaded(sorted)
                // ★ 확인은 **목록을 그린 뒤** 백그라운드에서 돈다.
                //
                //   클립 수만큼 `stat`을 도는데, 세션 20개 × 클립 10개가
                //   약 1 ms다(SPEC-0120). 작지만 메인 액터에서 돌면 그
                //   1 ms가 프레임 예산 안에 들어가고, 실기기에서 더 느리면
                //   목록이 뜨는 것 자체가 늦어진다.
                let locator = locator
                return .run { send in
                    let checked = await Task.detached(priority: .utility) {
                        var result: [UUID: ClipAvailability] = [:]
                        result.reserveCapacity(sorted.count)
                        // ★ **끝나지 않은 세션은 건너뛴다.** 레코드의
                        //   클립이 0개라 그대로 태우면 "영상이 없습니다"가
                        //   뜨고, 같은 행의 "복구할 수 있습니다"와
                        //   모순된다 — 영상은 디스크에 있다.
                        for session in sorted where !session.isUnfinished {
                            result[session.id] = ClipAvailability.of(session, locator: locator)
                        }
                        return result
                    }.value
                    await send(.availabilityChecked(checked))
                }

            case .availabilityChecked(let checked):
                // 그 사이에 목록을 다시 읽었으면 버린다 — 지난 확인 결과를
                // 새 목록에 붙이면 엉뚱한 세션에 경고가 붙는다.
                guard case .loaded(let sessions) = state.phase else { return .none }
                let ids = Set(sessions.map(\.id))
                state.availability = checked.filter { ids.contains($0.key) }
                return .none

            case .failed(let reason):
                state.phase = .failed("기록을 읽지 못했습니다 — \(reason)")
                return .none

            case .sessionTapped(let id):
                // 끝나지 않은 세션은 요약으로 보내지 않는다 — 보여줄
                // 클립이 레코드에 없다. **리듀서가 가른다**: 뷰에 맡기면
                // 다른 입구가 생길 때 빠뜨린다.
                if case .loaded(let sessions) = state.phase,
                   let session = sessions.first(where: { $0.id == id }),
                   session.isUnfinished {
                    return .send(.recoverRequested(id))
                }
                return .send(.delegate(.sessionTapped(id)))

            case .recoverRequested(let id):
                guard case .loaded(let sessions) = state.phase,
                      let session = sessions.first(where: { $0.id == id }),
                      session.isUnfinished
                else { return .none }
                // 시트를 **먼저** 띄우고 숫자는 나중에 채운다. 목록이
                // 확인 전에 그려지는 것과 같은 순서다.
                state.recovering = RecoverTarget(session, whenText: Self.whenText(session.startedAt))
                let orphans = orphans
                return .run { send in
                    await send(.orphansCounted(id, await orphans.orphans(for: session).count))
                }

            case .orphansCounted(let id, let count):
                // 그 사이에 시트를 닫았거나 다른 세션을 열었으면 버린다.
                guard state.recovering?.sessionID == id else { return .none }
                state.recovering?.clipCount = count
                return .none

            case .recoverDismissed:
                state.recovering = nil
                return .none

            case .recoverConfirmed:
                guard let target = state.recovering,
                      case .loaded(let sessions) = state.phase,
                      // 시트를 띄운 뒤 목록이 바뀔 수 있다. 다시 찾는다.
                      let session = sessions.first(where: { $0.id == target.sessionID })
                else {
                    state.recovering = nil
                    return .none
                }
                state.recovering = nil
                let recover = RecoverSessionUseCase(repository: repository, orphans: orphans)
                let now = now
                return .run { send in
                    do {
                        switch try await recover.execute(session, now: now()) {
                        case .recovered:
                            await send(.recoverFinished(.success(session.id)))
                        case .nothingToRecover:
                            // 시트를 띄운 뒤 파일이 사라졌다. 조용히 넘기면
                            // 사용자는 복구된 줄 안다.
                            await send(.recoverFinished(.failure(
                                Action.DeleteError(reason: "영상을 찾지 못했습니다")
                            )))
                        }
                    } catch {
                        await send(.recoverFinished(.failure(
                            Action.DeleteError(reason: error.localizedDescription)
                        )))
                    }
                }

            case .discardConfirmed:
                guard let target = state.recovering,
                      case .loaded(let sessions) = state.phase,
                      let session = sessions.first(where: { $0.id == target.sessionID })
                else {
                    state.recovering = nil
                    return .none
                }
                state.recovering = nil
                let discard = DiscardSessionUseCase(
                    repository: repository, files: files, orphans: orphans
                )
                return .run { send in
                    do {
                        switch try await discard.execute(session) {
                        case .discarded:
                            await send(.discardFinished(.success(session.id)))
                        case .alreadyClosed:
                            // 지우지 않았다. 목록을 다시 읽어 지금 상태를
                            // 보여준다 — 손으로 고치면 레코드와 어긋난다.
                            await send(.discardSkipped)
                        }
                    } catch {
                        // ⚠️ **파일은 이미 지워졌다.** 되돌리지 않는다 —
                        //    #126과 같은 결정이다.
                        await send(.discardFinished(.failure(
                            Action.DeleteError(reason: error.localizedDescription)
                        )))
                    }
                }

            case .recoverFinished(.success):
                // 목록을 다시 읽는다. 그 세션의 클립 수·스윙 수가 바뀌었고,
                // 손으로 고치면 두 곳이 어긋난다.
                return .send(.appeared)

            case .recoverFinished(.failure(let error)):
                state.deleteFailure = "복구하지 못했습니다 — \(error.reason)"
                return .none

            case .discardFinished(.success(let id)):
                guard case .loaded(let sessions) = state.phase else { return .none }
                state.phase = .loaded(sessions.filter { $0.id != id })
                state.availability[id] = nil
                return .none

            case .discardFinished(.failure(let error)):
                state.deleteFailure = "폐기하지 못했습니다 — \(error.reason)"
                return .none

            case .discardSkipped:
                state.deleteFailure = "그 사이에 세션이 끝나 폐기하지 않았습니다"
                return .send(.appeared)

            case .deleteRequested(let id):
                // **아직 지우지 않는다.** 지울 것을 적어서 보여주고 묻는다.
                guard case .loaded(let sessions) = state.phase,
                      let session = sessions.first(where: { $0.id == id })
                else { return .none }
                // ★ **끝나지 않은 세션은 이 경로로 지울 수 없다.**
                //
                //   `DeleteSessionUseCase`는 레코드의 `clips`를 돌며 파일을
                //   지우는데 미완 세션의 레코드에는 클립이 0개다. 그대로
                //   태우면 레코드만 사라지고 **고아 `.mov`가 영구히 남는다**
                //   — 복구도 폐기도 못 하는 상태이고 사용자가 지울 수단이
                //   없다. 확인 문구도 거짓이 된다("스윙 0개 · 클립 0개").
                //
                //   폐기는 복구 시트가 한다. 거기서는 스캔 결과로 센다.
                guard !session.isUnfinished else {
                    return .send(.recoverRequested(id))
                }
                state.deleting = .session(session, dateText: Self.dateText(session.startedAt))
                return .none

            case .deleteCancelled:
                state.deleting = nil
                return .none

            case .deleteConfirmed:
                guard let target = state.deleting,
                      case .session(let id) = target.kind,
                      case .loaded(let sessions) = state.phase,
                      // 확인을 띄운 뒤 목록이 바뀔 수 있다. **다시 찾는다** —
                      // 들고 있던 값을 지우면 그 사이에 바뀐 것을 지운다.
                      let session = sessions.first(where: { $0.id == id })
                else {
                    state.deleting = nil
                    return .none
                }
                state.deleting = nil
                let useCase = DeleteSessionUseCase(repository: repository, files: files)
                return .run { send in
                    do {
                        try await useCase.execute(session)
                        await send(.deleteFinished(.success(session.id)))
                    } catch {
                        // ⚠️ **파일은 이미 지워졌다.** 되돌리지 않는다 —
                        //    지운 파일을 복원할 방법이 없다. 남는 것은
                        //    "영상이 없는 레코드"이고 #120이 그것을
                        //    정직하게 보여준다.
                        await send(.deleteFinished(.failure(
                            Action.DeleteError(reason: error.localizedDescription)
                        )))
                    }
                }

            case .deleteFinished(.success(let id)):
                // 목록에서 바로 뺀다. 다시 읽으면 어차피 없지만, 그 사이에
                // 지운 행이 남아 있으면 **지워지지 않은 것처럼 보인다.**
                guard case .loaded(let sessions) = state.phase else { return .none }
                state.phase = .loaded(sessions.filter { $0.id != id })
                state.availability[id] = nil
                return .none

            case .deleteFinished(.failure(let error)):
                // 조용히 넘기면 사용자는 지워진 줄 안다. 실제로는 영상만
                // 사라지고 레코드가 남았다.
                state.deleteFailure = "지우지 못했습니다 — \(error.reason)"
                return .none

            case .deleteFailureDismissed:
                state.deleteFailure = nil
                return .none

            case .captureTapped:
                return .send(.delegate(.goToCapture))

            case .delegate:
                return .none
            }
        }
    }

    /// 확인 다이얼로그에 적는 날짜. 뷰의 포매터를 쓰지 않는다 — 리듀서가
    /// 만든 문구를 뷰가 그대로 그려야 테스트가 그 문구를 고정할 수 있다.
    /// 복구 시트의 "11월 5일 · 09:12". 날짜만 쓰는 `dateText`와 달리
    /// **시각까지 적는다** — 같은 날 여러 번 찍으면 날짜만으로는 어느
    /// 세션인지 알 수 없다.
    static func whenText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 · HH:mm"
        return formatter.string(from: date)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

}
