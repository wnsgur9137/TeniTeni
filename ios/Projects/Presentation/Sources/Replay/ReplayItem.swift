import Domain
import Foundation

/// 리플레이 플레이리스트의 한 칸. **단위는 스윙이다.**
///
/// 클립이 아니라 스윙으로 세는 이유는 사용자가 "34개 중 12번째"로 세기
/// 때문이다 — 요약이 보여주는 수도 스윙 수다. 클립 단위로 두면 그 번호를
/// 말할 수 없다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 1.
public struct ReplayItem: Equatable, Identifiable, Sendable {

    public let clipID: UUID
    public let fileName: String
    public let swing: Swing
    /// **클립의** fps. 세션의 값을 쓰지 않는다 — 발열로 강등되면 클립마다
    /// 다르고(ADR-0005), 그러면 "프레임 하나"의 길이가 틀린다.
    public let clipFPS: Int
    /// 사용자가 보는 번호. 1부터 센다.
    public let position: Int
    public let total: Int

    public var id: UUID { swing.id }

    public init(
        clipID: UUID,
        fileName: String,
        swing: Swing,
        clipFPS: Int,
        position: Int,
        total: Int
    ) {
        self.clipID = clipID
        self.fileName = fileName
        self.swing = swing
        self.clipFPS = clipFPS
        self.position = position
        self.total = total
    }

    /// 한 프레임의 길이. fps가 0 이하로 저장된 클립에서도 0으로 나누지 않는다.
    public var frameSeconds: TimeInterval {
        clipFPS > 0 ? 1 / Double(clipFPS) : 1 / 30
    }
}

extension ReplayItem {

    /// 세션을 펼쳐 플레이리스트를 만든다.
    ///
    /// **다시 정렬하지 않는다.** `SwiftDataSessionRepository`가 클립을
    /// `recordedAt` 순, 클립 안의 스윙을 `startSeconds` 순으로 돌려준다.
    /// 정렬을 두 곳에 두면 한쪽을 고칠 때 다른 쪽이 남는다.
    public static func playlist(from session: Session) -> [ReplayItem] {
        let flattened = session.clips.flatMap { clip in
            clip.swings.map { (clip: clip, swing: $0) }
        }
        let total = flattened.count
        return flattened.enumerated().map { offset, pair in
            ReplayItem(
                clipID: pair.clip.id,
                fileName: pair.clip.fileName,
                swing: pair.swing,
                clipFPS: pair.clip.fps,
                position: offset + 1,
                total: total
            )
        }
    }
}
