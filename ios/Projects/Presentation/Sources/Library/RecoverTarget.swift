import Domain
import Foundation

/// 복구 / 폐기 시트가 그릴 것. **리듀서가 문구를 만든다** —
/// 뷰가 포매팅하면 테스트가 문구를 고정할 수 없다(`DeleteTarget`과 같은 이유).
///
/// 목업: docs/06-디자인/_canvas/RecoverSheet.dc.html
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 6
public struct RecoverTarget: Equatable, Identifiable, Sendable {

    public let sessionID: UUID
    /// "11월 5일 · 09:12"
    public let whenText: String
    /// "볼머신 · 내 스윙" — **레코드에서 온다.** 고아 `.mov`만으로는
    /// 복원되지 않는 값이고, 그래서 촬영 시작 시 레코드를 연다.
    public let situationText: String
    /// "120fps"
    public let fpsText: String

    /// 디스크에서 찾은 클립 수. **`nil`이면 아직 확인 중이다.**
    ///
    /// ⚠️ `session.clips.count`가 아니다. 미완 세션의 레코드에는 클립이
    /// 0개이므로 그 값을 적으면 **항상 "클립 0개"**가 되고, #126이 확인
    /// 문구를 "절차가 아니라 확인"으로 만든 근거가 무너진다.
    public var clipCount: Int?

    public var id: UUID { sessionID }

    /// 복구할 수 있는가. 영상이 하나도 없으면 **폐기만 제안한다** —
    /// 첫 프레임이 오기 전에 죽은 세션이다.
    public var canRecover: Bool { (clipCount ?? 0) > 0 }

    public init(
        sessionID: UUID,
        whenText: String,
        situationText: String,
        fpsText: String,
        clipCount: Int? = nil
    ) {
        self.sessionID = sessionID
        self.whenText = whenText
        self.situationText = situationText
        self.fpsText = fpsText
        self.clipCount = clipCount
    }

    public init(_ session: Session, whenText: String) {
        self.init(
            sessionID: session.id,
            whenText: whenText,
            situationText: "\(session.situation.label) · \(session.observable.label)",
            fpsText: "\(session.fps)fps"
        )
    }
}
