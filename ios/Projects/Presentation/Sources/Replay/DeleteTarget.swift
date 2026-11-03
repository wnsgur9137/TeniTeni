import Domain
import Foundation

/// 확인 다이얼로그가 읽는 값.
///
/// ## 왜 값 타입인가
///
/// **"정말 지울까요?"만 묻는 것은 확인이 아니라 절차다.** 무엇이
/// 사라지는지 숫자로 적어야 하고, 그 문구가 틀리면 사용자가 **다른 것을
/// 지운다.** 그래서 문구 생성을 뷰에서 떼어내 값으로 고정한다.
///
/// 되돌리기가 없으므로(SPEC-0126 선택지 3) **이 문구가 유일한 안전장치**다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 3·4
public struct DeleteTarget: Equatable, Sendable, Identifiable {

    /// 무엇을 지우는가.
    public enum Kind: Equatable, Sendable {
        /// 세션 전체. **`id`를 담는다** — 확인을 띄운 뒤 목록이 바뀔 수
        /// 있고, 문구로 대조하면 그 사이에 바뀐 것을 지운다.
        case session(id: UUID)
        /// 클립 하나. `isLast`면 세션도 함께 사라진다.
        case clip(id: UUID, isLast: Bool)
    }

    public let kind: Kind
    /// 지울 세션. 클립 삭제도 세션 안에서 일어난다.
    public let sessionID: UUID
    public let title: String
    /// 어느 세션인가 — 날짜·상황.
    public let detail: String
    /// 무엇이 사라지는가 — 스윙·클립 수.
    public let counts: String
    /// 되돌릴 수 없다는 고지. **마지막 클립이면 세션도 간다고 말한다.**
    public let warning: String

    public var id: String {
        switch kind {
        case .session(let id): "session-\(id.uuidString)"
        case .clip(let id, _): "clip-\(id.uuidString)"
        }
    }

    /// 마지막 클립인가. 뷰가 경고를 강조하는 데 쓴다.
    public var isLastClip: Bool {
        if case .clip(_, let isLast) = kind { return isLast }
        return false
    }

    // MARK: - 만들기

    /// 세션 전체를 지운다.
    public static func session(_ session: Session, dateText: String) -> DeleteTarget {
        DeleteTarget(
            kind: .session(id: session.id),
            sessionID: session.id,
            title: "이 세션을 지울까요?",
            detail: "\(dateText) · \(session.situation.label)",
            counts: counts(swings: session.swingCount, clips: session.clips.count),
            warning: "영상을 함께 지우고, 되돌릴 수 없습니다."
        )
    }

    /// 클립 하나를 지운다.
    ///
    /// **마지막 클립이면 경고가 다르다.** 세션이 사라지는 것을 모르고
    /// 지우면 그것이 가장 나쁜 실수다.
    public static func clip(
        _ clip: Clip,
        in session: Session,
        dateText: String
    ) -> DeleteTarget {
        let isLast = session.clips.count <= 1
        return DeleteTarget(
            kind: .clip(id: clip.id, isLast: isLast),
            sessionID: session.id,
            title: isLast ? "마지막 클립입니다" : "이 클립을 지울까요?",
            detail: "\(dateText) · \(session.situation.label)",
            counts: counts(swings: clip.swings.count, clips: 1),
            warning: isLast
                ? "세션도 함께 지워집니다. 되돌릴 수 없습니다."
                : "영상을 함께 지우고, 되돌릴 수 없습니다."
        )
    }

    /// "스윙 12개 · 클립 3개". **0개도 적는다** — 스윙 0개 세션도 영상은
    /// 있고, 지우면 그 영상이 사라진다.
    static func counts(swings: Int, clips: Int) -> String {
        "스윙 \(swings)개 · 클립 \(clips)개"
    }
}
