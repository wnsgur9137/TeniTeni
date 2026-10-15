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
        ),
        // SwiftData는 스키마·cascade가 런타임에 결정된다. 컴파일만으로는
        // 아무것도 확인되지 않으므로 테스트 타깃이 필요하다.
        // 테스트 타깃이 있으면 scripts/verify-ios.sh가 build 대신 test를 돈다.
        .target(
            name: "DataTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.wnsgur9137.TeniTeni.DataTests",
            deploymentTargets: .iOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "Data")]
        )
    ]
)
