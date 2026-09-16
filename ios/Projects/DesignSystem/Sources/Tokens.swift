import SwiftUI

/// 디자인 시스템 토큰. **값의 정본은 `docs/06-디자인/DESIGN-SYSTEM.md` 11.2절**이고
/// 여기는 그것을 코드로 옮긴 것이다. 어긋나면 목업과 구현이 갈라진다 —
/// `TokenTests`가 hex를 고정한다.
///
/// 1-A에서 `DesignSystem` 모듈로 옮겼다 — `git mv` 한 번으로 끝났다
/// (docs/04-계획/WORK-PLAN.md 9.6절).
public enum Token {

    // MARK: 배경 · 표면

    public enum Background {
        public static let base = Color(hex: 0x0B0D0F)
        public static let surface = Color(hex: 0x16191D)
        public static let elevated = Color(hex: 0x1F2429)
        /// 영상 위 컨트롤 배경
        public static let scrim = Color(hex: 0x0B0D0F, opacity: 0.72)
    }

    // MARK: 텍스트

    public enum Text {
        public static let primary = Color(hex: 0xF2F4F6)
        public static let secondary = Color(hex: 0x9BA3AB)
        public static let tertiary = Color(hex: 0x6B737B)
        /// 라임 배경 위
        public static let onAccent = Color(hex: 0x0B0D0F)
    }

    // MARK: UI 팔레트 — 오버레이 위 레이어

    public enum State {
        public static let success = Color(hex: 0x3DDC84)
        /// 흔들림·발열·조명 경고
        public static let warning = Color(hex: 0xFF8A3D)
        public static let error = Color(hex: 0xFF4D4D)
        public static let info = Color(hex: 0x4DD8E6)
    }

    public enum Accent {
        /// CTA, 선택 상태, 지시형 피드백
        public static let primary = Color(hex: 0xC6F24E)
    }

    // MARK: 오버레이 팔레트 — 영상 위에만
    //
    // UI 팔레트와 섞지 않는다. 겹치면 "앱이 강조한 것"과
    // "몸에서 잘못된 것"을 구분하지 못한다.

    public enum Overlay {
        public static let bone = Color(hex: 0xFFFFFF, opacity: 0.72)
        /// 라켓 잡은 팔 — 시선 유도
        public static let racketArm = Color(hex: 0x4DD8E6)
        public static let joint = Color(hex: 0xFFFFFF)
        /// 문제 관절
        public static let issue = Color(hex: 0xFF4D4D)
        /// 공 궤적 (공 색과 연결)
        public static let trail = Color(hex: 0xFFD84D)
    }
}

extension Color {
    /// `0xRRGGBB` 표기를 그대로 받는다. 문서의 hex와 코드가 같은 모양이어야
    /// 대조가 눈으로 된다.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
