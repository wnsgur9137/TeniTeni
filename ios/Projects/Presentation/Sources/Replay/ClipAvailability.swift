import Domain
import Foundation

/// 세션의 클립 **파일**이 실제로 몇 개 남아 있는가.
///
/// ## 왜 필요한가
///
/// 레코드는 SwiftData, 영상은 `Documents` 아래에 있고 **둘은 따로
/// 사라진다** — 사용자가 파일 앱에서 지우거나, 저장공간 부족으로 iOS가
/// 정리하거나, 기기 이전·백업 복원에서 레코드만 온다.
///
/// 확인하지 않으면 목록이 **"스윙 12개"라고 말하고 열면 재생할 것이
/// 없다.** 레퍼런스 조사에서 반복된 불만이 "찾기 어렵다"가 아니라
/// **"사라졌다"**였고, 이것이 그 불만의 가장 나쁜 형태다.
///
/// ## 왜 세 단계인가
///
/// 세션 하나에 클립이 여럿이므로 **일부만 없을 수 있다.** 둘을 합치면
/// 클립 9개 중 1개가 없는 세션에도 "영상이 없습니다"가 붙는다. 사용자가
/// 열지 말지를 그 한 줄로 판단하므로 나눈다.
///
/// ## 왜 `Domain`이 아닌가
///
/// 파일 시스템을 보는 판단이고 `Domain`은 저장 매체를 모른다
/// ([D-03](../../../../../docs/05-결정/stack/D-03-architecture-pattern.md)).
///
/// 근거: docs/07-기획/SPEC-0120-missing-clip.md
public enum ClipAvailability: Equatable, Sendable {
    /// 전부 있다. **클립이 0개인 세션도 여기다** — 아래 참고.
    case all
    /// 일부 없다.
    case partial
    /// 전부 없다.
    ///
    /// ⚠️ **`none`이라고 이름 붙이지 마라.** 이 타입은 `ClipAvailability?`로
    /// 들려서(확인 전 = `nil`) `.none`이 쓰이는 자리마다 Swift가
    /// **`Optional.none`을 먼저 고른다.** 조용히 `nil`이 되고 컴파일은
    /// 통과한다 — 테스트가 그 함정에 걸려 한 번 잡아냈다.
    case missing

    /// 세션의 클립 파일을 확인한다.
    ///
    /// ⚠️ **클립이 0개면 `.all`이다.** 스윙 0개로 끝난 세션은 결손이
    /// 아니다 — 찍을 것이 없었을 뿐이고, 그 세션은 진단 화면이 맡는다
    /// ([SPEC-0110](../../../../../docs/07-기획/SPEC-0110-session-summary.md)).
    /// `.missing`으로 떨어뜨리면 **"영상이 없습니다"가 정상 세션에 붙는다.**
    ///
    /// ⚠️ **메인 액터에서 부르지 마라.** 클립 수만큼 `stat`을 돈다.
    /// 세션 20개 × 클립 10개 = 200회가 약 1 ms이지만, 그 1 ms가 프레임
    /// 예산 안에 들어가면 스크롤이 튄다.
    public static func of(_ session: Session, locator: ClipLocator) -> ClipAvailability {
        of(fileNames: session.clips.map(\.fileName), locator: locator)
    }

    /// 파일 이름 목록으로 확인한다. 세션 없이도 쓸 수 있다.
    public static func of(fileNames: [String], locator: ClipLocator) -> ClipAvailability {
        guard !fileNames.isEmpty else { return .all }
        var found = 0
        for name in fileNames where locator.url(for: name) != nil {
            found += 1
        }
        if found == fileNames.count { return .all }
        return found == 0 ? .missing : .partial
    }

    /// 화면에 적는 한 줄. 전부 있으면 `nil`이다.
    ///
    /// **"찍은 영상이 지워진 것은 아닙니다"를 쓰지 않는다.** `LibraryEmpty`의
    /// 읽기 실패 문구가 그것이고, 이 경우는 **실제로 파일이 없다.** 같은
    /// 말을 쓰면 두 상황이 구분되지 않는다.
    public var notice: String? {
        switch self {
        case .all: nil
        case .partial: "영상 일부 없음"
        case .missing: "영상이 없습니다"
        }
    }

    /// 열어서 볼 것이 하나라도 있는가.
    public var hasAnything: Bool { self != .missing }
}
