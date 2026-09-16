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
            ]
        ),
        // 테스트 타깃이 있으면 verify-ios.sh가 build 대신 test를 돈다.
        .target(
            name: "ApplicationTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.wnsgur9137.TeniTeni.ApplicationTests",
            deploymentTargets: .iOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "Application")]
        )
    ]
)
