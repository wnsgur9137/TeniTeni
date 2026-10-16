import ComposableArchitecture
import Domain
import Foundation

/// 촬영 탭의 루트. 상황 5종과, 시합일 때만 관찰 대상.
///
/// 선택은 항상 보인다 — 잘못 고르면 삼각대를 옮겨야 하고 그 비용이
/// 물리적이기 때문이다.
/// 근거: docs/06-디자인/IA-FLOW.md 10.4
@Reducer
public struct HomeFeature {

    @ObservableState
    public struct State: Equatable {
        public var situation: CaptureSituation
        public var observable: ObservationTarget

        /// 시합이 아니면 관찰 대상은 항상 `.swing`이다.
        public var effectiveObservable: ObservationTarget {
            cardObservable(for: situation)
        }

        /// 카드 한 장이 보여줄 관찰 대상. 고르지 않은 카드는 자기 기본값(`.swing`)을 유지한다 —
        /// 시합에서 라인 판정을 골랐다고 볼머신 카드의 배치까지 바뀌면 안 된다.
        public func cardObservable(for situation: CaptureSituation) -> ObservationTarget {
            guard situation == self.situation, situation.allowsLineCall else { return .swing }
            return observable
        }

        /// 카드 한 장이 그릴 값. 뷰가 전역 상태를 직접 읽지 않게 막는다 —
        /// 한 카드의 선택이 다섯 장에 번지던 결함(#73)이 그렇게 들어왔다.
        public struct Card: Equatable, Identifiable {
            public let situation: CaptureSituation
            public let isSelected: Bool
            public let showsObservablePicker: Bool
            public let observable: ObservationTarget

            public var id: CaptureSituation { situation }
        }

        public var cards: [Card] {
            CaptureSituation.allCases.map { situation in
                Card(
                    situation: situation,
                    isSelected: situation == self.situation,
                    showsObservablePicker: situation == self.situation && situation.allowsLineCall,
                    observable: cardObservable(for: situation)
                )
            }
        }

        public init(
            situation: CaptureSituation = .ballMachine,
            observable: ObservationTarget = .swing
        ) {
            self.situation = situation
            self.observable = observable
        }
    }

    public enum Action: Equatable {
        case situationSelected(CaptureSituation)
        case observableSelected(ObservationTarget)
        case startTapped
        case settingsTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case selectionChanged(CaptureSituation, ObservationTarget)
            case start(CaptureSituation, ObservationTarget)
            case openSettings
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .situationSelected(let situation):
                state.situation = situation
                // 시합에서 벗어나면 라인 판정 선택이 남아 있으면 안 된다.
                // 남겨두면 다시 시합을 골랐을 때 예전 선택이 되살아나
                // 사용자가 고른 적 없는 배치로 안내된다.
                if !situation.allowsLineCall { state.observable = .swing }
                return .send(.delegate(.selectionChanged(state.situation, state.effectiveObservable)))

            case .observableSelected(let target):
                guard state.situation.allowsLineCall else { return .none }
                state.observable = target
                return .send(.delegate(.selectionChanged(state.situation, state.effectiveObservable)))

            case .startTapped:
                return .send(.delegate(.start(state.situation, state.effectiveObservable)))

            case .settingsTapped:
                return .send(.delegate(.openSettings))

            case .delegate:
                return .none
            }
        }
    }
}
