import ProjectDescription

// 분석·렌더 엔진. UI에 의존하지 않으므로 iOS 앱과 macOS CLI가 공유한다.
// VisionKit이라는 이름을 쓰지 않는다 — Apple 프레임워크와 충돌한다.
let project = Project(
    name: "TeniVision",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ]
    ),
    targets: [
        .target(
            name: "TeniVision",
            destinations: [.iPhone, .mac],
            product: .framework,
            bundleId: "com.wnsgur9137.TeniTeni.TeniVision",
            deploymentTargets: .multiplatform(iOS: "26.0", macOS: "15.0"),
            sources: ["Sources/**"]
        )
    ]
)
