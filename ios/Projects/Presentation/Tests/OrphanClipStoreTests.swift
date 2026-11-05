import Domain
import Foundation
import Testing
@testable import Presentation

private let start = Date(timeIntervalSince1970: 1_700_000_000)

/// `stamp(for: start)`가 만드는 접두사. 테스트가 이것을 **직접 계산하지
/// 않는다** — 포맷이 바뀌면 구현과 함께 바뀌어야 하고, 손으로 적으면
/// 둘이 갈라진 것을 못 잡는다.
private var prefix: String { SwingPipeline.stamp(for: start) }

private func unfinished(clips: [Clip] = [], fps: Int = 120) -> Session {
    Session(
        startedAt: start,
        endedAt: nil,
        situation: .ballMachine,
        observable: .swing,
        fps: fps,
        clips: clips
    )
}

private func store(
    _ names: [String],
    probe: @escaping @Sendable (URL) async -> DocumentsOrphanClipStore.Probe? = { _ in
        DocumentsOrphanClipStore.Probe(createdAt: start, fps: 120)
    }
) -> DocumentsOrphanClipStore {
    DocumentsOrphanClipStore(
        directory: URL(filePath: "/clips"),
        contents: { _ in names },
        probe: probe
    )
}

/// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 2
@Suite("고아 클립 찾기")
struct DocumentsOrphanClipStoreTests {

    @Test("접두사가 맞는 .mov만 고른다")
    func 접두사() async {
        let found = await store([
            "\(prefix)-0.mov",
            "\(prefix)-1.mov",
            // 다른 세션.
            "20201231-235959-0.mov",
            // 사이드카 — 접두사를 공유하지만 확장자가 다르다.
            "\(prefix)-0.mov.overlay.json",
            "\(prefix)-0.mov.overlay.error",
            // 엉뚱한 것.
            "메모.txt",
            "\(prefix).mov",
        ]).orphans(for: unfinished())

        #expect(found.map(\.fileName) == ["\(prefix)-0.mov", "\(prefix)-1.mov"])
    }

    @Test("index 오름차순으로 준다")
    func 정렬() async {
        // 사전순이면 10이 2보다 앞에 온다. **숫자로 정렬해야 한다.**
        let found = await store([
            "\(prefix)-10.mov", "\(prefix)-2.mov", "\(prefix)-0.mov",
        ]).orphans(for: unfinished())

        #expect(found.map(\.index) == [0, 2, 10])
    }

    @Test("레코드가 이미 아는 클립은 제외한다")
    func 기존_제외() async {
        let known = Clip(fileName: "\(prefix)-0.mov", recordedAt: start, fps: 120)
        let found = await store([
            "\(prefix)-0.mov", "\(prefix)-1.mov",
        ]).orphans(for: unfinished(clips: [known]))

        #expect(found.map(\.fileName) == ["\(prefix)-1.mov"])
    }

    /// 파일에서 읽은 값을 쓴다 — 세션 fps를 그대로 쓰면 발열 강등을 걸친
    /// 세션이 틀어진다(ADR-0005).
    @Test("fps는 파일에서 읽는다")
    func fps_읽기() async {
        let found = await store(["\(prefix)-0.mov"], probe: { _ in
            .init(createdAt: start, fps: 60)
        }).orphans(for: unfinished(fps: 120))

        #expect(found.first?.fps == 60)
    }

    /// ⚠️ 0을 그대로 넣으면 재생 코드가 프레임 간격을 0으로 나눈다.
    @Test("fps를 못 읽거나 0이면 세션 값으로 떨어진다")
    func fps_폴백() async {
        for bad in [nil, 0, -30] {
            let found = await store(["\(prefix)-0.mov"], probe: { _ in
                .init(createdAt: start, fps: bad)
            }).orphans(for: unfinished(fps: 120))

            #expect(found.first?.fps == 120, "fps \(String(describing: bad))")
        }
    }

    /// ⚠️ **독립 리뷰가 찾은 것.** 버리면 그 파일은 복구도 폐기도 되지
    /// 않는 **영구 고아**가 된다 — 사용자가 지울 수단이 없다. 기획서가
    /// "`index` 순서를 유지하도록 `startedAt`에 `index`초를 더한다"로
    /// 정했는데 구현이 버리고 있었다.
    @Test("파일 속성을 못 읽어도 버리지 않고 순서를 지킨다")
    func 속성_실패() async {
        let found = await store(
            ["\(prefix)-0.mov", "\(prefix)-1.mov", "\(prefix)-2.mov"],
            probe: { _ in nil }
        ).orphans(for: unfinished())

        #expect(found.count == 3)
        #expect(found.map(\.index) == [0, 1, 2])
        // 시각이 index 순으로 벌어져 정렬이 살아 있다.
        #expect(found.map(\.recordedAt) == [
            start, start.addingTimeInterval(1), start.addingTimeInterval(2),
        ])
        // fps는 세션 값으로 떨어진다.
        #expect(found.allSatisfy { $0.fps == 120 })
    }

    /// 일부만 읽히는 경우. 읽힌 것은 파일 값, 못 읽은 것은 폴백.
    @Test("일부만 읽혀도 전부 복구 대상이다")
    func 속성_일부_실패() async {
        let found = await store(
            ["\(prefix)-0.mov", "\(prefix)-1.mov"],
            probe: { url in
                url.lastPathComponent.hasSuffix("-0.mov")
                    ? .init(createdAt: start.addingTimeInterval(500), fps: 60)
                    : nil
            }
        ).orphans(for: unfinished())

        #expect(found.count == 2)
        #expect(found[0].fps == 60)
        #expect(found[1].fps == 120)
    }

    @Test("디렉터리가 비어 있으면 빈 배열이다")
    func 빈_디렉터리() async {
        #expect(await store([]).orphans(for: unfinished()).isEmpty)
    }

    @Suite("파일명 판정")
    struct IndexTests {
        private let p = "20231114-221320"

        @Test("맨 이름만 통과한다")
        func 판정() {
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-0.mov", prefix: p) == 0)
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-12.mov", prefix: p) == 12)
            // 사이드카.
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-0.mov.overlay.json", prefix: p) == nil)
            // 다른 세션.
            #expect(DocumentsOrphanClipStore.index(of: "20201231-235959-0.mov", prefix: p) == nil)
            // 숫자가 아니다.
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-x.mov", prefix: p) == nil)
            // index가 없다.
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-.mov", prefix: p) == nil)
            #expect(DocumentsOrphanClipStore.index(of: "\(p).mov", prefix: p) == nil)
            // 빈 이름.
            #expect(DocumentsOrphanClipStore.index(of: "", prefix: p) == nil)
            // 경로 구분자가 섞인 것 — 숫자 파싱에서 걸린다.
            #expect(DocumentsOrphanClipStore.index(of: "\(p)-0/x.mov", prefix: p) == nil)
            #expect(DocumentsOrphanClipStore.index(of: "sub/\(p)-0.mov", prefix: p) == nil)
        }
    }

    /// 실제 파일 시스템에서 돈다. 기본 `contents`가 **하위 디렉터리로
    /// 내려가지 않는지**를 여기서만 확인할 수 있다.
    @Test("실제 디렉터리에서 하위 폴더를 보지 않는다")
    func 실제_파일() async throws {
        let root = URL.temporaryDirectory.appending(path: "orphan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([0]).write(to: root.appending(path: "\(prefix)-0.mov"))
        let sub = root.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        // 하위에 **같은 접두사**의 파일을 둔다. 걸리면 안 된다.
        try Data([0]).write(to: sub.appending(path: "\(prefix)-1.mov"))

        let found = await DocumentsOrphanClipStore(
            directory: root,
            // `.mov`가 진짜 영상이 아니므로 fps는 못 읽는다. 시각만 본다.
            probe: { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey])
                return values?.creationDate.map { .init(createdAt: $0, fps: nil) }
            }
        ).orphans(for: unfinished())

        #expect(found.map(\.fileName) == ["\(prefix)-0.mov"])
    }
}
