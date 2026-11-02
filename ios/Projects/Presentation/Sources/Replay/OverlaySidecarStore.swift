import Foundation
import TeniVision

/// 사이드카가 지금 어떤 상태인가.
///
/// **네 상태를 섞지 않는다.** 실패를 "준비 중"으로 보여주면 사용자는 영원히
/// 기다리고, "분석 전"을 실패로 보여주면 고칠 것이 없는데 다시 시도를
/// 누른다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md
public enum OverlaySidecarState: Equatable, Sendable {
    case ready(OverlaySidecar)
    /// 큐에 있고 아직 굽는 중이다.
    case baking
    /// 구웠는데 실패했다. 사유를 그대로 보여준다.
    case failed(String)
    /// 아직 큐에 들어가지도 않았다. 촬영 중에는 돌리지 않으므로 **정상
    /// 상태 중 하나다.**
    case notAnalyzed
}

/// 사이드카 파일을 읽고 쓴다.
///
/// 클립 파일 옆 `<클립>.overlay.json`에 둔다. 실패는 `<클립>.overlay.error`에
/// 사유를 적는다 — **앱을 닫아도 남아야** 다음에 열었을 때 "분석 전"과
/// 구분된다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md 선택지 1
public struct OverlaySidecarStore: Sendable {

    private let directory: URL

    public init(directory: URL = .documentsDirectory) {
        self.directory = directory
    }

    /// `FileManager`는 `Sendable`이 아니므로 **들고 있지 않는다.** 쓰는
    /// 자리에서 `.default`를 부른다 — 여기서 쓰는 연산(존재 확인·삭제)은
    /// 스레드 안전으로 문서화돼 있다.
    private var fileManager: FileManager { .default }

    func sidecarURL(for clipFileName: String) -> URL {
        directory.appending(path: clipFileName + ".overlay.json")
    }

    func errorURL(for clipFileName: String) -> URL {
        directory.appending(path: clipFileName + ".overlay.error")
    }

    /// 파일에서 읽은 상태. 큐의 상태는 모른다 — 합치는 쪽은 호출부다.
    ///
    /// 빈 이름은 디렉터리를 가리키므로 먼저 막는다(`ClipLocator`와 같은 함정).
    public func state(for clipFileName: String) -> OverlaySidecarState {
        guard !clipFileName.isEmpty else { return .notAnalyzed }

        let url = sidecarURL(for: clipFileName)
        if let data = try? Data(contentsOf: url) {
            do {
                let sidecar = try JSONDecoder().decode(OverlaySidecar.self, from: data)
                // 버전이 다르거나 짝이 안 맞으면 **쓰지 않는다.** 읽을 수 있는
                // 만큼 읽으면 빠진 필드가 기본값으로 채워져 틀린 오버레이를
                // 확신 있게 보여준다.
                guard sidecar.isUsable(for: clipFileName) else {
                    return .failed("오버레이 데이터가 이 클립과 맞지 않습니다")
                }
                return .ready(sidecar)
            } catch {
                return .failed("오버레이 데이터를 읽지 못했습니다")
            }
        }

        if let reason = try? String(contentsOf: errorURL(for: clipFileName), encoding: .utf8),
           !reason.isEmpty {
            return .failed(reason)
        }
        return .notAnalyzed
    }

    /// 사이드카를 저장한다. 성공하면 **이전 실패 기록을 지운다.**
    public func write(_ sidecar: OverlaySidecar, for clipFileName: String) throws {
        let encoder = JSONEncoder()
        // 사람이 열어 확인할 수 있어야 한다 — JSON을 고른 이유의 절반이다.
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(sidecar).write(to: sidecarURL(for: clipFileName), options: .atomic)
        try? fileManager.removeItem(at: errorURL(for: clipFileName))
    }

    /// 실패를 남긴다. 사유는 사용자가 읽는다.
    public func markFailed(_ reason: String, for clipFileName: String) {
        guard !clipFileName.isEmpty else { return }
        try? Data(reason.utf8).write(to: errorURL(for: clipFileName), options: .atomic)
    }

    /// 클립을 지울 때 함께 지운다. #126이 쓴다.
    public func remove(for clipFileName: String) {
        guard !clipFileName.isEmpty else { return }
        try? fileManager.removeItem(at: sidecarURL(for: clipFileName))
        try? fileManager.removeItem(at: errorURL(for: clipFileName))
    }
}
