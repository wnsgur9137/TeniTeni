import Foundation

/// 촬영 전에 정해져 있어야 하는 것들.
///
/// 온보딩을 마쳤다는 것은 **주 사용 손이 정해졌다**는 뜻이다. 둘을 따로
/// 두면 "온보딩은 끝났는데 손을 모르는" 상태가 생긴다.
public struct UserPreferences: Equatable, Sendable, Codable {
    public var handedness: Handedness?

    /// 홈이 "지난 선택을 미리 골라둔다"는 규칙을 지키려면 어딘가 남아야 한다
    /// (IA-FLOW 10.4). 세션 메타는 1-B에 생기므로 그때까지 여기 둔다.
    public var lastSituation: CaptureSituation
    public var lastObservable: ObservationTarget

    /// 스윙 감지음. IA-FLOW 10.5가 "소리가 화면보다 중요하다"고 정했으므로
    /// 기본값은 켜짐이다. 레슨에서는 코치를 방해할 수 있어 끄게 둔다.
    public var soundEnabled: Bool

    /// 리플레이에서 마지막으로 고른 오버레이 레이어.
    ///
    /// 기본은 `off`다 — **리플레이의 첫 화면은 자기 스윙 영상이어야 한다.**
    /// 오버레이는 사용자가 "보고 싶다"고 말한 뒤에 올라온다.
    ///
    /// 기억하는 이유는 `lastSituation`과 같다: 매번 다시 고르게 하지 않는다.
    public var lastOverlayLayer: OverlayLayer

    /// 주 사용 손이 있어야 촬영에 들어갈 수 있다.
    public var hasCompletedOnboarding: Bool { handedness != nil }

    public init(
        handedness: Handedness? = nil,
        lastSituation: CaptureSituation = .ballMachine,
        lastObservable: ObservationTarget = .swing,
        soundEnabled: Bool = true,
        lastOverlayLayer: OverlayLayer = .off
    ) {
        self.handedness = handedness
        self.lastSituation = lastSituation
        self.lastObservable = lastObservable
        self.soundEnabled = soundEnabled
        self.lastOverlayLayer = lastOverlayLayer
    }

    /// 저장된 JSON에 이 키가 없을 수 있다 — 기존 사용자의 설정이다.
    /// 기본 생성자의 값으로 떨어지게 한다. 없으면 디코딩이 **통째로**
    /// 실패해 설정 전체가 초기화된다.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handedness = try container.decodeIfPresent(Handedness.self, forKey: .handedness)
        lastSituation = try container.decodeIfPresent(CaptureSituation.self, forKey: .lastSituation)
            ?? .ballMachine
        lastObservable = try container.decodeIfPresent(ObservationTarget.self, forKey: .lastObservable)
            ?? .swing
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        lastOverlayLayer = try container.decodeIfPresent(OverlayLayer.self, forKey: .lastOverlayLayer)
            ?? .off
    }
}

/// 구현은 `Data`에 있다. `Domain`은 **무엇이 필요한지**만 말한다 —
/// 9.6의 의존성 방향 규칙.
public protocol UserPreferencesRepository: Sendable {
    func load() -> UserPreferences
    func save(_ preferences: UserPreferences)
}
