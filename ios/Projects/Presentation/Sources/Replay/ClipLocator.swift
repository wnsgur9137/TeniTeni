import Foundation

/// 클립 파일 이름을 **존재하는 URL**로 바꾼다. 없으면 `nil`이다.
///
/// 레코드는 SwiftData에, 파일은 `URL.documentsDirectory` 아래에 있다. 둘은
/// 따로 사라질 수 있다 — 저장공간 정리나 다른 앱이 파일을 옮기면 레코드만
/// 남는다. 그 경우를 **열기 전에** 알아야 플레이어 오류 문구가 아니라 설명을
/// 보여줄 수 있다.
///
/// 근거: docs/07-기획/SPEC-0123-swing-replay.md 선택지 6.
/// #120이 보관함 목록에서 같은 타입을 쓴다.
public struct ClipLocator: Sendable {

    private let directory: URL
    private let exists: @Sendable (URL) -> Bool

    public init(
        directory: URL = .documentsDirectory,
        exists: @escaping @Sendable (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        }
    ) {
        self.directory = directory
        self.exists = exists
    }

    /// 존재하면 URL, 없으면 `nil`.
    ///
    /// 빈 이름은 디렉터리 자신을 가리키게 되므로 먼저 막는다 — 디렉터리는
    /// 존재하므로 그대로 두면 "파일이 있다"가 되어 플레이어가 받는다.
    public func url(for fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        let candidate = directory.appending(path: fileName)
        return exists(candidate) ? candidate : nil
    }
}
