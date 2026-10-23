import ProjectDescription

let project = Project(
    name: "Presentation",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "Presentation",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.Presentation",
            deploymentTargets: .iOS("26.0"),
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "Domain", path: "../Domain"),
                .project(target: "DesignSystem", path: "../DesignSystem"),
                // 프레임 스트림은 TCA 바깥으로 흐른다 — D-03 필수 규칙.
                // 그래서 Presentation이 TeniVision을 직접 안다.
                .project(target: "TeniVision", path: "../TeniVision"),
                .external(name: "ComposableArchitecture"),
            ]
        ),
        // 세션 조립은 상대초 변환과 저장소 호출을 들고 있다 — 그것을
        // 확인할 자리가 없었다. 테스트 타깃이 있으면
        // scripts/verify-ios.sh가 build 대신 test를 돈다.
        .target(
            name: "PresentationTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.wnsgur9137.TeniTeni.PresentationTests",
            deploymentTargets: .iOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "Presentation")]
        )
    ]
)
