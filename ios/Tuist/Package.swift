// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

// 외부 패키지의 빌드 설정. 두 가지를 맞춘다.
//
// 1. 배포 타깃 — Tuist는 패키지 자체 매니페스트의 최소값을 그대로 쓴다.
//    SPM은 소비자 기준으로 올려주지만 Tuist는 안 올린다. Xcode 27의
//    시뮬레이터 SDK는 iOS 15 미만을 아예 거부하므로(13.0으로 두면
//    "range of supported deployment target versions is 15.0 to 27.1.x")
//    전부 15로 올린다.
//
//    ComposableArchitecture와 UIKitNavigation만 17이다. 그 둘이
//    NavigationStackController·_push(value:) 같은 iOS 17 API를 쓴다.
//    SwiftNavigation·Perception 계열은 17로 올리면 각각 다른 곳이 깨진다 —
//    _UIBindingWrapper의 @Observable 중복 적합, back-deploy 심의
//    "Bindable is unavailable". 15에 둔다.
//
// 2. 제품 형태 — TCA는 정적 프레임워크로 둔다.
//
// ⚠️ 언어 모드(`SWIFT_VERSION`)는 **지정하지 않는다.** 각 패키지의
//    swift-tools-version이 정한 것을 그대로 쓴다. 패키지들이 서로 다른
//    모드를 전제하므로 한 값으로 묶으면 반드시 어느 한쪽이 깨진다 —
//    5로 묶으면 DependenciesMacros가 `@MainActor` 클로저 오버로드를
//    구분하지 못해 "invalid redeclaration of 'IsolationCheck'",
//    6으로 묶으면 PerceptionCore의 Bindable이 "sending '$input_value'
//    risks causing data races"로 깨진다.
//
//    우리 모듈은 각 Project.swift에서 6 + strict concurrency를
//    유지한다 (D-04). 여기서 빼는 것은 외부 패키지에만 해당한다.
//
// 근거: docs/07-기획/SPEC-0061-module-shell.md
let packageSettings = PackageSettings(
    productTypes: [
        "ArgumentParser": .staticFramework,
        "ComposableArchitecture": .staticFramework,
    ],
    baseSettings: .settings(base: [
        "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
        "MACOSX_DEPLOYMENT_TARGET": "12.0",
    ]),
    // baseSettings는 프로젝트 수준이라 패키지 매니페스트가 만든 타깃 설정에
    // 덮인다. 타깃별로 직접 지정해야 실제로 올라간다.
    targetSettings: [
        "AppKitNavigation": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ArgumentParser": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ArgumentParserToolInfo": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "BasicContainers": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "BitCollections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CasePaths": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CasePathsCore": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CasePathsMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CasePathsMacrosSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Clocks": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Collections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CombineSchedulers": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ComposableArchitecture": ["IPHONEOS_DEPLOYMENT_TARGET": "17.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ComposableArchitectureMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ConcurrencyExtras": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ConcurrencyExtrasTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "ContainersPreview": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "CustomDump": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Dependencies": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "DependenciesMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "DependenciesMacrosPlugin": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "DependenciesTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "DequeModule": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "HashTreeCollections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "HeapModule": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "IdentifiedCollections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "InternalCollectionsUtilities": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "IssueReporting": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "IssueReportingTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "OrderedCollections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Perception": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "PerceptionCore": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "PerceptionMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Sharing": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Sharing1": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "Sharing2": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SortedCollections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftBasicFormat": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftCompilerPlugin": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftCompilerPluginMessageHandling": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftDiagnostics": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftIDEUtils": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftIfConfig": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftLexicalLookup": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftLibraryPluginProvider": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftNavigation": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftNavigationMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftOperators": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftParser": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftParserDiagnostics": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftRefactor": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax509": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax510": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax600": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax601": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax602": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax603": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntax604": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntaxBuilder": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntaxMacroExpansion": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntaxMacros": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntaxMacrosGenericTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftSyntaxMacrosTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftUINavigation": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "SwiftWarningControl": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "TrailingElementsModule": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "UIKitNavigation": ["IPHONEOS_DEPLOYMENT_TARGET": "17.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "UIKitNavigationShim": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "XCTestDynamicOverlay": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "_RopeModule": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "_SwiftLibraryPluginProviderCShims": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "_SwiftSyntaxCShims": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "_SwiftSyntaxGenericTestSupport": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "combine-schedulers": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-argument-parser": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-case-paths": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-clocks": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-collections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-composable-architecture": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-composable-architecture_ComposableArchitecture": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-concurrency-extras": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-custom-dump": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-dependencies": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-identified-collections": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-issue-reporting": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-navigation": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-perception": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-sharing": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-sharing_Sharing": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "swift-syntax": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
        "xctest-dynamic-overlay": ["IPHONEOS_DEPLOYMENT_TARGET": "15.0", "MACOSX_DEPLOYMENT_TARGET": "12.0"],
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
    ]
)
