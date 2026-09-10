import ProjectDescription

// Phase 0-A: 단일 타깃. 모듈 분리는 Phase 1-A에서 수행한다.
// 근거: docs/04-계획/WORK-PLAN.md 9.6절 "도입 순서 — 필요할 때 만든다"
let project = Project(
    name: "TeniTeni",
    options: .options(
        defaultKnownRegions: ["ko"],
        developmentRegion: "ko"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "TeniTeni",
            destinations: .iOS,
            product: .app,
            bundleId: "com.wnsgur9137.TeniTeni",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .file(path: "TeniTeni/Resources/Info.plist"),
            sources: ["TeniTeni/Sources/**"],
            resources: []
        )
    ]
)
