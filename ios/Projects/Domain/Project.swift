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
        ),
        // 삭제 순서(파일 먼저 → 레코드)가 **이 모듈에 있고** 그것이
        // #126의 핵심이다 — 어느 쪽이 먼저냐가 "실패했을 때 남는 상태"를
        // 정한다. 확인할 자리가 없었다.
        //
        // 테스트 타깃이 있으면 scripts/verify-ios.sh가 build 대신 test를
        // 돈다(`PresentationTests`와 같은 이유).
        .target(
            name: "DomainTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.wnsgur9137.TeniTeni.DomainTests",
            deploymentTargets: .iOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [.target(name: "Domain")]
        ),
    ]
)
