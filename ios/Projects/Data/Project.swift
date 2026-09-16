import ProjectDescription

let project = Project(
    name: "Data",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "Data",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.Data",
            deploymentTargets: .iOS("26.0"),
            sources: ["Sources/**"],
            // Repository 구현이 Domain 프로토콜을 따른다. 방향은 Data → Domain 한쪽뿐이다.
            dependencies: [
                .project(target: "Domain", path: "../Domain")
            ]
        )
    ]
)
