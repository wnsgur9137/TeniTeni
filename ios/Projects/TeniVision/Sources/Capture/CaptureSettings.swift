import Foundation

/// 촬영 품질. 사용자가 선택한다.
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.2절
public enum CaptureQuality: String, CaseIterable, Sendable, Identifiable {
    case precise   // 120fps
    case standard  // 60fps

    public var id: String { rawValue }

    public var fps: Double {
        switch self {
        case .precise: 120
        case .standard: 60
        }
    }

    public var title: String {
        switch self {
        case .precise: "정밀 (120fps)"
        case .standard: "표준 (60fps)"
        }
    }

    /// 정확도 차이를 반드시 표시한다. 사용자가 배터리를 아끼려 60을 골랐을 때
    /// 궤적 검출률이 떨어지는 인과를 모르면 앱이 부정확하다고 판단하게 된다.
    public var detail: String {
        switch self {
        case .precise: "공 궤적을 더 정확하게 추적합니다. 배터리와 저장 공간을 더 사용합니다."
        case .standard: "배터리와 저장 공간을 아낍니다. 빠른 공은 놓칠 수 있습니다."
        }
    }
}

/// 노출 설정. 셔터 속도가 프레임레이트보다 궤적 검출에 중요하다.
/// 시속 100km 공은 1/60s 노출에서 107px 번진다 (공 자체는 15px).
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.3절
public enum ExposureSetting: String, CaseIterable, Sendable, Identifiable {
    case auto
    case fast1000   // 1/1000s — 실외 맑음 (권장)
    case fast500    // 1/500s  — 실외 흐림
    case fast250    // 1/250s  — 실내 밝은 조명

    public var id: String { rawValue }

    /// nil이면 자동 노출
    public var duration: CMTimeValueSpec? {
        switch self {
        case .auto: nil
        case .fast1000: .init(numerator: 1, denominator: 1000)
        case .fast500: .init(numerator: 1, denominator: 500)
        case .fast250: .init(numerator: 1, denominator: 250)
        }
    }

    public var title: String {
        switch self {
        case .auto: "자동"
        case .fast1000: "1/1000"
        case .fast500: "1/500"
        case .fast250: "1/250"
        }
    }

    public var detail: String {
        switch self {
        case .auto: "번짐이 심해 궤적 검출이 어렵습니다"
        case .fast1000: "실외 맑음 (권장)"
        case .fast500: "실외 흐림"
        case .fast250: "실내 밝은 조명"
        }
    }
}

public struct CMTimeValueSpec: Sendable, Equatable {
    public let numerator: Int32
    public let denominator: Int32
}

/// 촬영 거리 프리셋. 궤적 파라미터의 전제가 된다.
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.1절 (권장 6m, 허용 5~8m)
public enum DistancePreset: Double, CaseIterable, Sendable, Identifiable {
    case near = 5
    case recommended = 6
    case far = 8

    public var id: Double { rawValue }
    public var title: String { "\(Int(rawValue))m" }
}
