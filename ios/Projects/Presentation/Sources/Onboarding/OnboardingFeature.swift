import ComposableArchitecture
import Domain
import Foundation

/// 소개 → 주 사용 손. **두 단계뿐이다.**
///
/// 권한은 별도 화면을 두지 않는다. 소개 화면이 이미 "카메라와 마이크 권한이
/// 필요합니다"를 적었고, 같은 말을 한 화면 더 하면 온보딩만 길어진다.
/// 근거: docs/07-기획/SPEC-0064-entry-screens.md 구현 선택지 2
@Reducer
public struct OnboardingFeature {

    public enum Step: Int, Equatable, Sendable, CaseIterable {
        case intro
        case handedness

        /// 스텝 인디케이터에 쓴다. 1부터 센다.
        public var number: Int { rawValue + 1 }
        public static var total: Int { allCases.count }
    }

    @ObservableState
    public struct State: Equatable {
        public var step: Step
        /// 아직 정해지지 않았으면 `nil`. 고르지 않고는 다음으로 갈 수 없다.
        public var handedness: Handedness?

        public init(step: Step = .intro, handedness: Handedness? = nil) {
            self.step = step
            self.handedness = handedness
        }
    }

    public enum Action: Equatable {
        case startTapped
        case handednessSelected(Handedness)
        case finishTapped
        /// 부모(`AppFeature`)가 받아 저장한다. Feature 간 직접 의존을 막는
        /// D-03 규칙 때문에 자식이 저장소를 직접 부르지 않는다.
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case completed(Handedness)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startTapped:
                state.step = .handedness
                return .none

            case .handednessSelected(let hand):
                state.handedness = hand
                return .none

            case .finishTapped:
                // 손이 없으면 아무 일도 하지 않는다. 버튼이 비활성이지만
                // 상태 쪽에서도 막는다 — 뷰만 믿으면 조용히 통과한다.
                guard let hand = state.handedness else { return .none }
                return .send(.delegate(.completed(hand)))

            case .delegate:
                return .none
            }
        }
    }
}
