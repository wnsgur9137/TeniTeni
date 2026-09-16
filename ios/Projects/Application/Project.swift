import ProjectDescription

let project = Project(
    name: "Application",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "Application",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.Application",
            deploymentTargets: .iOS("26.0"),
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "Presentation", path: "../Presentation"),
                .project(target: "Data", path: "../Data"),
                .external(name: "ComposableArchitecture"),
                // TCA가 `@_exported import Clocks`를 하는데 Tuist가 전이로는
                // swift-clocks 프로젝트를 만들지 않는다. 직접 걸어 강제한다.
                .external(name: "Clocks"),
            ]
        )
    ]
)
