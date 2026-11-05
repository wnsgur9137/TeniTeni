import AVFoundation
import Domain
import Foundation

/// `Documents`에서 **레코드가 모르는 클립**을 찾는다.
///
/// `Domain`이 선언한 `OrphanClipStore`의 구현이다. 디렉터리 스캔과
/// `AVAsset` 읽기가 **여기 한 곳에만** 있다 — `Domain`은 둘 다 할 수 없다
/// (아키텍처 2.2: "순수 Swift, 의존성 0").
///
/// ## 어떻게 찾는가
///
/// 파일명 접두사가 이미 세션 id 역할을 한다. `SwingPipeline.open(at:)`이
/// `ClipRecorder`의 `stamp`와 `SessionBuilder`의 `startedAt`을 **같은
/// `pending.startedAt`에서** 만들기 때문이다.
///
/// ```
/// 레코드 startedAt  2026-11-05 09:12:34 UTC
///        ↓ SwingPipeline.stamp(for:)
/// 접두사  "20261105-091234"
///        ↓ Documents 평면 스캔
/// 파일    20261105-091234-0.mov · 20261105-091234-1.mov · …
/// ```
///
/// 추측이 아니라 기계적 일치다.
///
/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 2
public struct DocumentsOrphanClipStore: OrphanClipStore {

    /// 파일 하나에서 읽어야 하는 것. 테스트가 이것을 대신 준다.
    public struct Probe: Sendable {
        /// 녹화가 **시작된** 시각.
        public let createdAt: Date
        /// `.mov` 트랙의 실제 fps. 못 읽으면 `nil`.
        public let fps: Int?

        public init(createdAt: Date, fps: Int?) {
            self.createdAt = createdAt
            self.fps = fps
        }
    }

    private let directory: URL
    private let contents: @Sendable (URL) -> [String]
    private let probe: @Sendable (URL) async -> Probe?

    public init(
        directory: URL = .documentsDirectory,
        contents: @escaping @Sendable (URL) -> [String] = { url in
            // **하위 디렉터리로 내려가지 않는다.** 맨 이름만 본다 —
            // `DocumentsClipFileStore.isSafe`가 막는 것과 같은 함정이다.
            (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        },
        probe: @escaping @Sendable (URL) async -> Probe? = Self.read
    ) {
        self.directory = directory
        self.contents = contents
        self.probe = probe
    }

    public func orphans(for session: Session) async -> [OrphanClip] {
        let prefix = SwingPipeline.stamp(for: session.startedAt)
        let known = Set(session.clips.map(\.fileName))

        var found: [OrphanClip] = []
        for name in contents(directory).sorted() {
            guard !known.contains(name) else { continue }
            guard let index = Self.index(of: name, prefix: prefix) else { continue }
            guard let probed = await probe(directory.appending(path: name)) else { continue }
            found.append(
                OrphanClip(
                    fileName: name,
                    index: index,
                    recordedAt: probed.createdAt,
                    // 못 읽으면 세션 시작 시점의 값으로 떨어진다. 발열
                    // 강등을 걸친 세션에서는 틀릴 수 있지만, 0이나 음수를
                    // 넣으면 재생 코드가 프레임 간격을 0으로 나눈다.
                    fps: probed.fps.map { $0 > 0 ? $0 : session.fps } ?? session.fps
                )
            )
        }
        return found.sorted { $0.index < $1.index }
    }

    /// 이 세션의 클립인가, 그러면 몇 번째인가.
    ///
    /// | 파일명 | 결과 | 왜 |
    /// |---|---|---|
    /// | `20261105-091234-2.mov` | `2` | |
    /// | `20261105-091234-2.mov.overlay.json` | `nil` | `.mov`로 끝나지 않는다 |
    /// | `20261031-180000-0.mov` | `nil` | 다른 세션 |
    /// | `20261105-091234-x.mov` | `nil` | 숫자가 아니다 |
    ///
    /// 사이드카가 접두사를 공유하지만 확장자로 갈린다.
    static func index(of fileName: String, prefix: String) -> Int? {
        let head = prefix + "-"
        guard fileName.hasPrefix(head), fileName.hasSuffix(".mov") else { return nil }
        let middle = fileName.dropFirst(head.count).dropLast(".mov".count)
        guard !middle.isEmpty else { return nil }
        return Int(middle)
    }

    /// 파일에서 시각과 fps를 읽는다.
    ///
    /// `creationDate`를 쓰는 이유: `contentModificationDate`는 녹화가
    /// **끝난** 시각이고, 정상 경로의 `recordedAt`은 시작 시각이다.
    public static func read(_ url: URL) async -> Probe? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        guard let createdAt = values?.creationDate ?? values?.contentModificationDate else {
            // 파일이 없거나 속성을 못 읽는다. 복구 대상으로 세지 않는다 —
            // 시각을 모르면 목록에서 어디에 놓을지도 모른다.
            return nil
        }

        let asset = AVURLAsset(url: url)
        let rate = try? await asset.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate)
        return Probe(
            createdAt: createdAt,
            fps: rate.flatMap { $0 }.map { Int($0.rounded()) }
        )
    }
}
