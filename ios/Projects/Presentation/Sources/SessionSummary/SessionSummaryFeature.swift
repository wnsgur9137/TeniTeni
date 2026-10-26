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

        public init(sessionID: UUID, phase: Phase = .loading) {
            self.sessionID = sessionID
            self.phase = phase
        }

        /// 스윙이 하나도 없으면 요약이 아니라 **진단**이다.
        ///
        /// 빈 요약을 보여주면 사용자는 앱이 고장났다고 판단한다 — IA-FLOW.
        public var isDiagnosis: Bool {
            guard case .loaded(let session) = phase else { return false }
            return session.swingCount == 0
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
        case failed(String)
        /// 세션이 저장소에 없다. 저장이 실패했거나 지워졌다.
        case missing
        case closeTapped
        case retryTapped
        /// 진단 화면의 "배치 다시 보기".
        case reframeTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case closed
            /// 진단 화면의 "배치 다시 보기". 촬영 전 단계로 돌아간다.
            ///
            /// **그 세션이 찍던 상황을 그대로 들고 간다.** 설정에서 추론하면
            /// 그 사이 사용자가 홈에서 다른 상황을 골랐을 때 엉뚱한 배치
            /// 안내를 보여준다.
            case reframe(situation: CaptureSituation, observable: ObservationTarget)
        }
    }

    private let repository: any SessionRepository

    public init(repository: any SessionRepository) {
        self.repository = repository
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared, .retryTapped:
                state.phase = .loading
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
