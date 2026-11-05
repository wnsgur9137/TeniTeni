import ComposableArchitecture
import Domain
import Foundation

/// 촬영이 끝난 뒤, 또는 보관함에서 들어와 세션 하나를 보여준다.
///
/// ## 왜 id만 받고 다시 읽는가
///
/// 세션을 통째로 받아 상태에 실으면 촬영 직후와 보관함이 **다른 코드**가
/// 된다. [IA-FLOW](../../../../../docs/06-디자인/IA-FLOW.md)는 둘을 "같은
/// 목적지"로 정했다. 게다가 **저장이 실제로 됐는지도 이 읽기로 드러난다** —
/// 넘겨받은 값을 그리면 저장 실패를 영원히 모른다.
///
/// ## 왜 0개 판정을 여기서 하는가
///
/// 읽기 **전에는** 요약인지 진단인지 알 수 없다. Feature를 둘로 나누면
/// 같은 로딩 코드가 둘 생기고, 어느 쪽을 띄울지 정하려면 어차피 읽어야 한다.
///
/// 근거: docs/07-기획/SPEC-0110-session-summary.md
@Reducer
public struct SessionSummaryFeature {

    @ObservableState
    public struct State: Equatable {
        public let sessionID: UUID
        public var phase: Phase
        /// 파일이 없는 클립. **클립 단위다** — 세션 하나에 클립이 여럿이고
        /// 일부만 없을 수 있다(SPEC-0120 선택지 3).
        ///
        /// 비어 있으면 "전부 있다"가 아니라 **"아직 확인하지 않았다"일 수도
        /// 있다.** 요약은 확인 전에 먼저 그려지고, 그 사이에는 경고가 없다 —
        /// 거짓을 말하는 시간이 짧아지는 것이 목적이고 0이 되는 것은 아니다.
        public var missingClips: Set<UUID>

        public init(
            sessionID: UUID,
            phase: Phase = .loading,
            missingClips: Set<UUID> = []
        ) {
            self.sessionID = sessionID
            self.phase = phase
            self.missingClips = missingClips
        }

        /// 그 클립의 영상이 없는가.
        public func isMissing(_ clipID: UUID) -> Bool { missingClips.contains(clipID) }

        /// 스윙이 하나도 없으면 요약이 아니라 **진단**이다.
        ///
        /// 빈 요약을 보여주면 사용자는 앱이 고장났다고 판단한다 — IA-FLOW.
        ///
        /// ⚠️ **복구된 세션은 제외한다.** `Session.needsDiagnosis`가 그
        /// 판정을 들고 있다 — 여기와 뷰가 각각 조건을 적고 있어서 한쪽만
        /// 고치면 어긋났다.
        public var isDiagnosis: Bool {
            guard case .loaded(let session) = phase else { return false }
            return session.needsDiagnosis
        }
    }

    public enum Phase: Equatable, Sendable {
        case loading
        case loaded(Session)
        /// 읽지 못했다. **사유를 보여준다** — 조용히 빈 화면을 띄우면
        /// 사용자는 찍은 것이 사라졌다고 읽는다.
        case failed(String)
    }

    public enum Action: Equatable {
        case appeared
        case loaded(Session)
        /// 클립 파일 확인이 끝났다. 요약이 그려진 **뒤에** 온다.
        case missingClipsChecked(Set<UUID>)
        case failed(String)
        /// 세션이 저장소에 없다. 저장이 실패했거나 지워졌다.
        case missing
        case closeTapped
        case retryTapped
        /// 진단 화면의 "배치 다시 보기".
        case reframeTapped
        /// 클립 행의 스윙을 눌렀다.
        case swingTapped(UUID)
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case closed
            /// 진단 화면의 "배치 다시 보기". 촬영 전 단계로 돌아간다.
            ///
            /// **그 세션이 찍던 상황을 그대로 들고 간다.** 설정에서 추론하면
            /// 그 사이 사용자가 홈에서 다른 상황을 골랐을 때 엉뚱한 배치
            /// 안내를 보여준다.
            case reframe(situation: CaptureSituation, observable: ObservationTarget)
            /// 리플레이로 보낸다. **Feature가 Feature를 띄우지 않는다** —
            /// 조립은 `Application`이 한다(D-03).
            case openReplay(sessionID: UUID, swingID: UUID)
        }
    }

    private let repository: any SessionRepository
    private let locator: ClipLocator

    public init(repository: any SessionRepository, locator: ClipLocator = ClipLocator()) {
        self.repository = repository
        self.locator = locator
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared, .retryTapped:
                state.phase = .loading
                // 지난 확인을 버린다. 그 사이에 지워졌을 수 있다.
                state.missingClips = []
                let id = state.sessionID
                // `self`를 포획하면 Reducer가 Sendable이 아니어서 막힌다.
                // 저장소만 지역으로 꺼내 넘긴다.
                let repository = repository
                return .run { send in
                    do {
                        guard let session = try await repository.load(id: id) else {
                            await send(.missing)
                            return
                        }
                        await send(.loaded(session))
                    } catch {
                        await send(.failed(error.localizedDescription))
                    }
                }

            case .loaded(let session):
                state.phase = .loaded(session)
                // ★ 확인은 **요약을 그린 뒤** 백그라운드에서 돈다.
                //   클립 수만큼 `stat`을 돈다 — 메인 액터에서 돌리지 않는다.
                let locator = locator
                return .run { send in
                    let missing = await Task.detached(priority: .utility) {
                        Set(
                            session.clips
                                .filter { locator.url(for: $0.fileName) == nil }
                                .map(\.id)
                        )
                    }.value
                    await send(.missingClipsChecked(missing))
                }

            case .missingClipsChecked(let missing):
                // 그 사이에 다시 읽었으면 버린다 — 지난 결과를 새 세션에
                // 붙이면 엉뚱한 클립에 경고가 붙는다.
                guard case .loaded(let session) = state.phase else { return .none }
                let ids = Set(session.clips.map(\.id))
                state.missingClips = missing.intersection(ids)
                return .none

            case .failed(let reason):
                state.phase = .failed("기록을 읽지 못했습니다 — \(reason)")
                return .none

            case .missing:
                // 저장이 실패했을 수도, 지워졌을 수도 있다. 어느 쪽이든
                // 사용자에게는 "없다"가 사실이다.
                state.phase = .failed("이 세션의 기록이 없습니다")
                return .none

            case .closeTapped:
                return .send(.delegate(.closed))

            case .swingTapped(let swingID):
                // ★ 영상이 없는 클립의 스윙은 **열지 않는다.**
                //
                //   열면 `ReplayMissing`이 뜨는데, 열리기 전에 알 수 있으면
                //   여는 비용(화면 전환·방향 잠금)을 치를 이유가 없다.
                //   리플레이의 그 화면은 **그대로 둔다** — 요약을 보는 사이에
                //   지워질 수 있고, 그때 마지막 그물이 된다.
                //   **아는 경우에만 막는다.** "세션이 로드돼 있어야 한다"로
                //   막으면 로드 전에는 아무 스윙도 열 수 없게 되는데, 그것은
                //   이 변경이 바꾸려던 동작이 아니다 — 모르면 보내고,
                //   리플레이의 `ReplayMissing`이 받는다.
                if case .loaded(let session) = state.phase,
                   let owner = session.clips.first(where: { clip in
                       clip.swings.contains { $0.id == swingID }
                   }),
                   state.isMissing(owner.id) {
                    return .none
                }
                // 세션이 아니라 `id`를 넘긴다 — 리플레이가 다시 읽는다
                // (SPEC-0110 선택지 1).
                return .send(.delegate(.openReplay(
                    sessionID: state.sessionID, swingID: swingID
                )))

            case .reframeTapped:
                // 읽은 세션이 있어야 상황을 안다. 없으면 보낼 것이 없다.
                guard case .loaded(let session) = state.phase else { return .none }
                return .send(.delegate(.reframe(
                    situation: session.situation, observable: session.observable
                )))

            case .delegate:
                return .none
            }
        }
    }
}
