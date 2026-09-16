import Foundation

/// 촬영 전에 정해져 있어야 하는 것들.
///
/// 온보딩을 마쳤다는 것은 **주 사용 손이 정해졌다**는 뜻이다. 둘을 따로
/// 두면 "온보딩은 끝났는데 손을 모르는" 상태가 생긴다.
public struct UserPreferences: Equatable, Sendable, Codable {
    public var handedness: Handedness?

    /// 주 사용 손이 있어야 촬영에 들어갈 수 있다.
    public var hasCompletedOnboarding: Bool { handedness != nil }

    public init(handedness: Handedness? = nil) {
        self.handedness = handedness
    }
}

/// 구현은 `Data`에 있다. `Domain`은 **무엇이 필요한지**만 말한다 —
/// 9.6의 의존성 방향 규칙.
public protocol UserPreferencesRepository: Sendable {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}
