// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: ["ArgumentParser": .staticFramework]
)
#endif

// 외부 의존성은 개발 도구(TeniTool)에만 쓴다.
// 앱과 TeniVision은 의존성 0을 유지한다 — SPEC-0006 구현 선택지 2.
let package = Package(
    name: "TeniTeniDependencies",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.5.0"),
    ]
)
