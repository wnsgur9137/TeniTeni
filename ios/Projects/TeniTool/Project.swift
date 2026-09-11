import ProjectDescription

// 0-C 오프라인 검증 도구. macOS 전용 단일 실행 파일이며
// 서브커맨드로 기능을 나눈다 (synth / analyze / label / sweep).
// 근거: docs/07-기획/SPEC-0006-synthetic-video.md 구현 선택지 1
//
// 로직은 TeniToolKit에 둔다. 실행 파일의 심볼은 테스트 번들에서 링크할 수
// 없으므로(앱과 달리 bundle_loader를 쓸 수 없다), 실행 파일은 @main만 갖는
// 껍데기로 두고 테스트는 라이브러리를 본다.
let project = Project(
    name: "TeniTool",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
    ]),
    targets: [
        .target(
            name: "TeniToolKit",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.TeniToolKit",
            deploymentTargets: .macOS("15.0"),
            sources: ["Kit/**"],
            dependencies: [
                .project(target: "TeniVision", path: "../TeniVision"),
                .external(name: "ArgumentParser"),
            ]
        ),
        .target(
            name: "TeniTool",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "com.wnsgur9137.TeniTeni.TeniTool",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/**"],
            dependencies: [.target(name: "TeniToolKit")]
        ),
        .target(
            name: "TeniToolTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.wnsgur9137.TeniTeni.TeniToolTests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "TeniToolKit")]
        ),
    ]
)
