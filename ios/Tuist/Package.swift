// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "ArgumentParser": .staticFramework,
        "ComposableArchitecture": .staticFramework,
    ],
    // Tuist는 패키지의 자체 최소 배포 타깃(TCA는 iOS 13)을 그대로 쓴다.
    // SPM은 소비자 기준으로 올려주는데 Tuist는 안 올린다 — 그래서 TCA의
    // UIKit 내비게이션(iOS 17+)이 컴파일되지 않는다.
    //
    // 17로 올린다. 26으로 올리면 swift-navigation의 Perception 심이
    // 네이티브 @Observable과 충돌한다(redundant conformance).
    baseSettings: .settings(base: [
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        // 외부 패키지는 Swift 5 언어 모드로 둔다. Tuist가 툴체인 기본값(6)을
        // 씌우는데, TCA는 자기 매니페스트에서 5 모드를 전제로 한 코드가 있어
        // `_SendableWritableKeyPath` 같은 곳에서 깨진다.
        // 우리 모듈은 각 Project.swift에서 6으로 유지한다 — D-04.
        "SWIFT_VERSION": "5.0",
    ]),
    // baseSettings는 프로젝트 수준이라 패키지 매니페스트가 만든 타깃 설정에
    // 덮인다. 타깃별로 직접 지정해야 실제로 올라간다.
    //
    // 26이 아니라 17인 이유: 26으로 올리면 swift-navigation의 Perception 심이
    // 네이티브 @Observable과 충돌한다(redundant conformance). 17이면 TCA의
    // UIKit 내비게이션 요구를 만족하면서 그 충돌을 피한다.
    //
    // Perception·PerceptionCore는 빼 둔다. 그 둘은 iOS 17 미만에 @Observable을
    // back-deploy하는 심이라, 17로 올리면 "Bindable is unavailable in iOS"로
    // 스스로를 막는다. 자기 매니페스트의 13을 그대로 쓰게 둔다.
    // TCA 하나만 올린다.
    //
    // TCA의 NavigationStackControllerUIKit.swift가 iOS 17 API를 쓰는데
    // Tuist는 패키지 자체 최소값(13)을 그대로 쓴다 — SPM은 소비자 기준으로
    // 올려주지만 Tuist는 안 올린다.
    //
    // 내비게이션 계열은 올리지 않는다. SwiftNavigation을 17로 올리면
    // _UIBindingWrapper가 네이티브 @Observable과 중복 적합이 되고,
    // Perception 계열을 올리면 back-deploy 심이 스스로를 막는다.
    targetSettings: [
        "ComposableArchitecture": ["IPHONEOS_DEPLOYMENT_TARGET": "17.0"],
    ]
)
#endif

// TeniVision은 의존성 0을 유지한다 — macOS CLI(TeniTool)와 같은 코드를 쓰므로
// 앱 전용 의존성이 들어가면 CLI가 못 쓴다 (SPEC-0006 구현 선택지 2).
//
// Presentation·Application은 TCA를 쓴다 — D-03이 정했고 SPEC-0061이 시점을 1-A로
// 정했다. 예전 주석이 "앱과 TeniVision은 의존성 0"이라 싸잡아 적었는데, 그 규칙의
// 실제 대상은 TeniVision뿐이다.
let package = Package(
    name: "TeniTeniDependencies",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
        // TCA가 `@_exported import Clocks`를 하는데, 전이 의존성만으로는
        // Tuist가 swift-clocks의 프로젝트를 생성하지 않아 모듈 해석이 깨진다.
        // 체크아웃은 되는데 워크스페이스에 안 들어간다. 직접 선언해 해결한다.
        .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.1.1"),
    ]
)
