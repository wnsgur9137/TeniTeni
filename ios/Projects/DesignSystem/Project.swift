import ProjectDescription

let project = Project(
    name: "DesignSystem",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "DesignSystem",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.DesignSystem",
            deploymentTargets: .iOS("26.0"),
            sources: ["Sources/**"],
            // 컬러·타이포 토큰뿐이다. 다른 계층을 알 필요가 없다.
            dependencies: []
        )
    ]
)
