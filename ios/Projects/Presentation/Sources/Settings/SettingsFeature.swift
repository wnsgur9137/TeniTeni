import ComposableArchitecture
import Domain
import Foundation

/// `촬영` 탭 우상단 기어로 들어온다. **탭이 아니다** — 할 일이 아니라
/// 준비이고 세션당 0~1회 쓴다.
/// 근거: docs/06-디자인/IA-FLOW.md 10.2 · 10.7
@Reducer
public struct SettingsFeature {

    @ObservableState
    public struct State: Equatable {
        public var handedness: Handedness
        public var soundEnabled: Bool

        public init(handedness: Handedness, soundEnabled: Bool = true) {
            self.handedness = handedness
            self.soundEnabled = soundEnabled
        }
    }

    public enum Action: Equatable {
        case handednessChanged(Handedness)
        case soundToggled(Bool)
        case closeTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case handednessChanged(Handedness)
            case close
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .handednessChanged(let hand):
                state.handedness = hand
                return .send(.delegate(.handednessChanged(hand)))

            case .soundToggled(let on):
                state.soundEnabled = on
                return .none

            case .closeTapped:
                return .send(.delegate(.close))

            case .delegate:
                return .none
            }
        }
    }
}
