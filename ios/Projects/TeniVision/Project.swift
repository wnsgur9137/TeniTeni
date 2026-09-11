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
            // 정적 프레임워크다. macOS CLI(TeniTool)는 앱 번들이 아니라
            // 프레임워크를 동봉할 자리가 없고, @rpath로 찾을 수도 없다.
            // 정적 링크면 양쪽이 같은 설정을 쓴다. 리소스가 없으므로
            // 정적으로 바꿔도 앱이 잃는 것이 없다.
            product: .staticFramework,
            bundleId: "com.wnsgur9137.TeniTeni.TeniVision",
            deploymentTargets: .multiplatform(iOS: "26.0", macOS: "15.0"),
            sources: ["Sources/**"]
        )
    ]
)
