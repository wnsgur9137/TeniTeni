import Domain
import Foundation
import TeniVision

/// 클립 파일과 **딸린 것 전부**를 지운다.
///
/// `Domain`이 선언한 `ClipFileStore`의 구현이다. 파일 경로 규칙과 사이드카
/// 이름 규칙이 **여기 한 곳에만** 있다 — `ClipLocator`(이름→URL)와
/// `OverlaySidecarStore`(사이드카 이름)를 그대로 쓴다.
///
/// 저장소(`Data`)가 파일까지 지우게 하면 그 규칙이 두 곳에 생기고 둘이
/// 어긋날 수 있다.
///
/// 근거: docs/07-기획/SPEC-0126-delete.md 선택지 1
public struct DocumentsClipFileStore: ClipFileStore {

    private let directory: URL
    private let sidecars: OverlaySidecarStore

    public init(
        directory: URL = .documentsDirectory,
        sidecars: OverlaySidecarStore = OverlaySidecarStore()
    ) {
        self.directory = directory
        self.sidecars = sidecars
    }

    /// 영상과 오버레이 사이드카를 지운다.
    ///
    /// **실패를 던지지 않는다.** 파일이 이미 없는 것은 실패가 아니다
    /// (#120의 상태) — 결과가 같다: 그 파일은 이제 없다.
    public func remove(fileName: String) async {
        guard Self.isSafe(fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
        // 사이드카는 클립과 수명이 같다(#121 선택지 1). 남겨도 짝이 안 맞아
        // 거부되지만, 용량을 먹는다 — #124가 다루는 바로 그 용량이다.
        sidecars.remove(for: fileName)
    }

    /// 지워도 되는 이름인가. **맨 이름만 받는다.**
    ///
    /// ## 왜 이 가드가 있는가
    ///
    /// 여기는 **지우는** 코드다. 틀리면 사용자가 고르지 않은 파일이
    /// 사라지고 되돌릴 수 없다. 가드는 세 줄이고 틀렸을 때의 대가는
    /// 그와 비교가 안 된다.
    ///
    /// | 이름 | `Documents/<이름>`을 해석하면 | 막는가 |
    /// |---|---|---|
    /// | `a.mov` | `Documents/a.mov` | 통과 |
    /// | `""` | **`Documents` 자신** | ✅ |
    /// | `../a.mov` | **`Documents`의 형제** | ✅ |
    /// | `sub/a.mov` | 하위 디렉터리 | ✅ |
    /// | `/etc/hosts` | `Documents/etc/hosts` — 탈출하지 않는다 | ✅(구분자로) |
    ///
    /// 절대 경로는 Foundation이 상대 성분으로 붙이므로 탈출하지 않지만,
    /// **`..`는 탈출한다** — `FileManager`가 해석한다.
    ///
    /// ## 지금 위험한가
    ///
    /// 아니다. `fileName`은 녹화가 만든 `url.lastPathComponent`이므로
    /// 구분자가 들어갈 수 없다. 그런데 그 값은 **SwiftData에 저장되고
    /// 백업 복원·기기 이전으로도 들어온다.** 우리가 만든 값만 온다는
    /// 보장이 영구적이지 않다.
    static func isSafe(_ fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        guard !fileName.contains("/") else { return false }
        // `..`는 그 자체로도, 성분으로도 막는다.
        guard fileName != ".", fileName != ".." else { return false }
        return true
    }
}
