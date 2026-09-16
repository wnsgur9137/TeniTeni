import ProjectDescription

// 1-A에서 계층을 분리했다. 앱 타깃은 진입점만 갖고 Application에 위임한다.
// 근거: docs/04-계획/WORK-PLAN.md 9.6절, docs/07-기획/SPEC-0061-module-shell.md
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
            // JUNHYEOK LEE 개인 팀. Xcode에서 손으로 고르면
            // tuist generate가 덮어쓰므로 매니페스트에 둔다.
            "DEVELOPMENT_TEAM": "VW2UR5Y845",
            "CODE_SIGN_STYLE": "Automatic",
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
            resources: [],
            dependencies: [
                // 진입점은 Application만 안다. 나머지는 그 아래로 숨는다.
                .project(target: "Application", path: "Projects/Application")
            ]
        )
    ]
)
