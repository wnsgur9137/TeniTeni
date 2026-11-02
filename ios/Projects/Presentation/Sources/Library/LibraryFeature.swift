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

        public init(
            phase: Phase = .loading,
            availability: [UUID: ClipAvailability] = [:]
        ) {
            self.phase = phase
            self.availability = availability
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
        /// 빈 상태의 "촬영하러 가기".
        case captureTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case sessionTapped(UUID)
            /// 빈 상태에서 촬영 탭으로 보낸다. "없다"만 말하고 끝내면
            /// 사용자는 다음에 무엇을 할지 모른다.
            case goToCapture
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
                        for session in sorted {
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
                return .send(.delegate(.sessionTapped(id)))

            case .captureTapped:
                return .send(.delegate(.goToCapture))

            case .delegate:
                return .none
            }
        }
    }
}
