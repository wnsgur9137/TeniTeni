import ArgumentParser

/// 0-C 오프라인 검증 도구의 루트 커맨드.
/// 서브커맨드로 기능을 나눈다 — 공용 입출력·JSON 포맷을 한 곳에 둔다.
/// 근거: docs/07-기획/SPEC-0006-synthetic-video.md 구현 선택지 1
public struct Teni: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "teni",
        abstract: "TeniTeni 오프라인 검증 도구",
        discussion: """
            Phase 0-C의 게이트 판정을 위한 도구 모음입니다.
            궤적 검출률 측정 방법은 docs/02-설계/CAPTURE-PROTOCOL.md 5.5절에 있습니다.
            """,
        subcommands: [Synth.self, Analyze.self]
    )

    public init() {}
}
