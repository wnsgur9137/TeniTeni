import Domain
import Foundation

/// `UserPreferences`를 `UserDefaults`에 둔다.
///
/// 값이 둘뿐이고 세션마다 한 번 읽는다. SwiftData는 1-E에서 세션·클립을
/// 담을 때 들어온다 — 설정 두 개를 위해 먼저 끌어오지 않는다.
public struct UserDefaultsUserPreferencesRepository: UserPreferencesRepository {
    /// `UserDefaults`는 `Sendable`이 아니다. 스레드 안전하다고 문서화돼
    /// 있지만 타입 시스템이 모르므로 `nonisolated(unsafe)`로 명시한다.
    /// 그렇게 적는 편이 struct를 actor로 바꾸는 것보다 정직하다 —
    /// 실제로 안전한 것을 안전하다고 말할 뿐이다.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let key = "com.wnsgur9137.TeniTeni.userPreferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data)
        else {
            return UserPreferences()
        }
        return decoded
    }

    public func save(_ preferences: UserPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
