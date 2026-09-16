import ProjectDescription

let project = Project(
    name: "Domain",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "Domain",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.Domain",
            deploymentTargets: .iOS("26.0"),
            sources: ["Sources/**"],
            // 의존성이 없다. 9.6의 규칙 — Domain은 Foundation 외에 아무것도 import하지 않는다.
            // 여기에 무언가 추가하려면 그 전에 규칙을 고쳐야 한다.
            dependencies: []
        )
    ]
)
