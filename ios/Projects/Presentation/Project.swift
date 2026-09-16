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
                // TCA가 `@_exported import Clocks`를 하는데 Tuist가 전이로는
                // swift-clocks 프로젝트를 만들지 않는다. 직접 걸어 강제한다.
                .external(name: "Clocks"),
            ]
        )
    ]
)
