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
    ///
    /// 빈 이름은 디렉터리 자신을 가리키므로 먼저 막는다. 막지 않으면
    /// **`Documents`를 통째로 지우려 든다** — `ClipLocator`와 같은 함정이고
    /// 여기서는 결과가 훨씬 나쁘다.
    public func remove(fileName: String) async {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
        // 사이드카는 클립과 수명이 같다(#121 선택지 1). 남겨도 짝이 안 맞아
        // 거부되지만, 용량을 먹는다 — #124가 다루는 바로 그 용량이다.
        sidecars.remove(for: fileName)
    }
}
