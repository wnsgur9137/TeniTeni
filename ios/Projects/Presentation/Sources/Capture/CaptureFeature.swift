import ComposableArchitecture
import Domain

/// 촬영 한 번. **프레이밍 가이드에서 시작해** 촬영으로 넘어간다.
///
/// 두 단계를 한 Feature에 둔 이유는 카메라 세션을 한 번만 세우기 위해서다.
/// 화면을 쪼개면 세션을 두 번 세우거나 넘겨야 한다.
///
/// 근거: docs/07-기획/SPEC-0078-start-capture.md · docs/06-디자인/IA-FLOW.md 10.3
@Reducer
public struct CaptureFeature {

    @ObservableState
    public struct State: Equatable {
        /// 촬영 중에 바뀌지 않는다. 바꾸려면 나가서 다시 고른다 —
        /// 삼각대를 옮겨야 하는 선택이다.
        public let situation: CaptureSituation
        public let observable: ObservationTarget
        public var phase: Phase

        public var guidance: FramingGuidance { .make(for: observable) }

        /// 무엇을 찍는지. 잘못 골랐다면 삼각대를 옮기기 전에 알아야 한다.
        public var subject: String { "\(situation.label) · \(observable.label)" }

        public init(
            situation: CaptureSituation,
            observable: ObservationTarget,
            phase: Phase = .framing
        ) {
            self.situation = situation
            self.observable = observable
            self.phase = phase
        }
    }

    public enum Phase: Equatable, Sendable {
        case framing
        case capturing
    }

    public enum Action: Equatable {
        case startTapped
        case closeTapped
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case finished
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                // 촬영 중에 다시 눌릴 일은 없지만, 단계를 되돌리지 않는다는 것을
                // 상태로도 막는다.
                guard state.phase == .framing else { return .none }
                state.phase = .capturing
                return .none

            case .closeTapped:
                return .send(.delegate(.finished))

            case .delegate:
                return .none
            }
        }
    }
}
