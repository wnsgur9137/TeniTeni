---
title: "iOS 기술 스택"
aliases: ["iOS 기술 스택", "iOS Stack"]
tags:
  - 문서유형/설계
  - 영역/iOS
created: 2026-09-10
updated: 2026-09-11
status: active
---

# 05. iOS 기술 스택

> 기술 스택 결정은 [결정 현황](../05-결정/DECISION-LOG.md)에서 **22/22 완료**됐습니다.
> ✅는 결정 노트가 있거나 그에 수반되는 항목, 🟡는 관례적 선택으로 착수 시 확인할 항목입니다.

## 5.1 로컬 환경

확인된 개발 환경입니다.

| 항목 | 버전 |
|---|---|
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 |
| Tuist | 4.110.0 (mise 관리) |
| XcodeGen | 설치됨 |
| Node | 24.9.0 |
| Python | 3.9.6 (시스템) — 프로젝트용 3.12 별도 필요 |
| Docker | 설치됨 |

## 5.2 스택 요약

| 레이어 | 잠정안 | 상태 | 대안 |
|---|---|---|---|
| 언어 | Swift 6.x (strict concurrency) | ✅ | 격리 설계는 [동시성 문서](../02-설계/CONCURRENCY.md) |
| 최소 타깃 | **iOS 26.0** | ✅ | [D-01](../05-결정/stack/D-01-deployment-target.md)에서 확정 |
| UI | SwiftUI + `@Observable` | ✅ | [D-02](../05-결정/stack/D-02-ui-framework.md)에서 확정 |
| 아키텍처 | Clean Architecture + **TCA** | ✅ | [D-03](../05-결정/stack/D-03-architecture-pattern.md)에서 확정 |
| 비동기 | Swift Concurrency + TCA Effect | ✅ | [D-04](../05-결정/stack/D-04-concurrency.md)에서 확정 |
| 카메라 | AVFoundation | ✅ | — |
| 비전 | Vision (신규 Swift API) + Core ML | ✅ | [D-06](../05-결정/stack/D-06-pose-engine.md)에서 확정 |
| 오버레이 렌더 | **Metal** (프리뷰 직접 렌더) | ✅ | [D-07](../05-결정/stack/D-07-overlay-rendering.md)에서 확정 |
| 녹화 | AVAssetWriter | ✅ | — |
| 로컬 DB | SwiftData | ✅ | [D-08](../05-결정/stack/D-08-local-db.md)에서 확정 |
| 시계열 저장 | 파일 (Protobuf) | ✅ | [D-09](../05-결정/stack/D-09-serialization.md)에서 확정 |
| 네트워크 | **Moya** (+ Alamofire) | ✅ | [D-11](../05-결정/stack/D-11-networking.md)에서 확정 |
| DI | swift-dependencies (TCA 내장) | ✅ | [D-12](../05-결정/stack/D-12-dependency-injection.md)에서 확정 |
| 모듈 빌드 | Tuist 4 | ✅ | [D-05](../05-결정/stack/D-05-module-tooling.md)에서 확정 |
| 수치 연산 | Accelerate / simd | ✅ | — |
| 로깅 | OSLog | 🟡 | swift-log |
| 크래시/분석 | Firebase Crashlytics | ✅ | [D-13](../05-결정/stack/D-13-observability.md)에서 확정 |
| 린트 | SwiftLint + SwiftFormat | 🟡 | — |
| 테스트 | Swift Testing + XCTest | 🟡 | Quick/Nimble |
| 배포 | Fastlane → TestFlight | 🟡 | Xcode Cloud |

## 5.3 주요 선택의 근거

### 최소 타깃 iOS 26.0

✅ **확정** — [D-01](../05-결정/stack/D-01-deployment-target.md) (2026-09-10)

핵심 근거는 **Vision 프레임워크가 iOS 18부터 Swift 네이티브로 재설계**됐다는 점입니다. 레거시 `VN*` 클래스는 Apple 문서에서 *"Original Objective-C and Swift API"* 로 분류됐고, 클래스 + completion handler 구조라 Swift 6 strict concurrency와 계속 충돌합니다.

iOS 18이 아니라 26을 택한 이유는 **레거시 분기를 아예 만들지 않기 위해서**입니다. 1인 개발에서 `if #available` 이중 경로는 그 자체로 비용입니다.

확정에 따라 함께 정해진 것:

| 항목 | 내용 |
|---|---|
| Vision API | `DetectHumanBodyPoseRequest`, `DetectTrajectoriesRequest` (struct, `Sendable`, async/await) |
| 손 관절 | `detectsHands = true` — body + hands를 한 요청으로 |
| 상태 관리 | `@Observable` |
| 카메라 회전 | `AVCaptureDevice.RotationCoordinator` |
| 영속화 | SwiftData 사용 가능 (D-08에서 판단) |

### 전면 SwiftUI

✅ **확정** — [D-02](../05-결정/stack/D-02-ui-framework.md) (2026-09-10)

기존 프로젝트는 UIKit + RxSwift + SnapKit 조합이었으나, 신규에서는 전면 SwiftUI로 갑니다.

결정적이었던 것은 **명령형 영역(카메라)이 어느 쪽을 택해도 `UIViewRepresentable` 경계 안에 갇힌다**는 점입니다. UIKit을 택해서 얻는 이점이 실질적으로 없는 반면, 오버레이(`Canvas`)와 진척도(Swift Charts)는 SwiftUI에서만 공짜로 얻습니다.

| 영역 | 구현 |
|---|---|
| 카메라 프리뷰 | `UIViewRepresentable` → **`MTKView`** (Metal 직접 렌더, [D-07](../05-결정/stack/D-07-overlay-rendering.md)) |
| 스켈레톤·궤적 오버레이 | **Metal 렌더 패스** (영상과 같은 draw) |
| 그 외 전 화면 | SwiftUI |
| 상태 | `@Observable` |

**RxSwift는 도입하지 않습니다.** UI 프레임워크와 무관한 별개 사안으로 D-04에서 확정하지만, 방향은 정해져 있습니다 — 비디오 프레임 파이프라인은 분석이 밀릴 때 프레임을 버려야 하는데(백프레셔) Rx의 기본 동작은 버퍼링이라 메모리가 터집니다.

### 네트워크: Moya

✅ **확정** — [D-11](../05-결정/stack/D-11-networking.md) (2026-09-10)

엔드포인트를 `TargetType` enum으로 선언해 API 표면을 한눈에 봅니다. 스텁 응답이 내장되어 서버 없이 Data 계층을 테스트할 수 있습니다.

**절충안**: `contracts/openapi.yaml`에서 DTO만 생성하고 전송은 Moya가 담당하면, 스펙 변경이 모델 레벨에서는 컴파일 타임에 잡힙니다. Phase 2 착수 시 판단합니다.

⬜ Phase 2에서 Moya/Alamofire의 Swift 6 strict concurrency 대응 상태를 확인해야 합니다.

### 아키텍처: Clean Architecture + TCA

✅ **확정** — [D-03](../05-결정/stack/D-03-architecture-pattern.md) (2026-09-10)

계층 분리는 Clean Architecture, Presentation 계층은 TCA입니다. MVVM은 TCA와 같은 자리를 차지하므로 채택하지 않습니다.

#### ⚠️ 필수 규칙: 프레임 스트림은 TCA 바깥

**초당 60회 프레임 이벤트를 Reducer 액션으로 흘리면 안 됩니다.** 액션 로깅이 무용지물이 되고 디스패치 오버헤드가 프레임 예산을 잠식합니다.

| 경로 | 빈도 | 처리 |
|---|---|---|
| 포즈·궤적 프레임 | 60fps | `AsyncStream` → `@Observable` 오버레이 상태. **Store 경유 금지** |
| 스윙 검출, 세션 상태, 발열, 녹화 완료 | 초당 수 회 이하 | Reducer 액션 |

```
TeniVision (TCA 바깥)
  프레임 → 포즈/궤적 → 스무딩 → 오버레이 상태
    ↓ AsyncStream, 60fps
  CaptureView 오버레이 레이어가 직접 구독

  ↓ 의미 있는 사건만
Store / Reducer
  .swingDetected / .sessionStateChanged / .thermalWarning / .recordingFinished
```

### 모듈 빌드: Tuist 4

✅ **확정** — [D-05](../05-결정/stack/D-05-module-tooling.md) (2026-09-10)

TCA 채택으로 Feature 모듈마다 Reducer·View·Store가 세트로 생기므로 모듈 템플릿화의 가치가 커졌습니다. TCA 매크로로 빌드 시간이 늘어나는 만큼, 모듈 분리로 증분 빌드 범위를 좁히는 것도 실익입니다.

**Phase 0 예외**: 기술 검증 단계는 단일 타깃으로 시작하고 Phase 1에서 모듈 구조로 재편합니다.

## 5.4 모듈 구조

```
ios/
├── Tuist/
│   ├── Config.swift
│   └── ProjectDescriptionHelpers/     # 모듈 템플릿
├── Workspace.swift
└── Projects/
    ├── Application/                   # 앱 진입점, DI Composition Root, 라우팅
    ├── Presentation/                  # 화면 단위 TCA Feature
    │   ├── Capture/
    │   ├── Analysis/
    │   ├── Session/
    │   ├── Library/
    │   ├── Progress/
    │   └── Onboarding/
    ├── Domain/                        # Entity, UseCase, Repository 프로토콜 — 의존성 0
    ├── Data/                          # Repository 구현, SwiftData 영속화, 파일 저장소
    ├── Network/                       # Moya TargetType, DTO, 인증 인터셉터
    ├── TeniVision/                    # 분석·렌더 엔진 — destinations: [.iPhone, .mac]
    ├── TeniTool/                      # 0-C 검증 CLI (macOS 전용) — teni
    ├── MLModels/                      # .mlpackage + 로더 (Git LFS)
    ├── DesignSystem/                  # 컬러, 타이포, 공용 컴포넌트
    └── Core/                          # Logger, Extensions, 공용 유틸
```

**모듈 도입은 한 번에 하지 않습니다.** 각 모듈이 필요해지는 시점이 다릅니다 — [작업 순서 9.6](../04-계획/WORK-PLAN.md#96-tuist-모듈-구성) 참고. `TeniVision`이 0-C에서 가장 먼저 분리되는데, **macOS CLI 분석 도구와 코드를 공유해야 하기 때문**입니다.

### 멀티플랫폼 모듈 규약

`TeniVision`은 iOS 앱과 macOS CLI가 함께 씁니다. 단일 타깃으로 양쪽을 만듭니다 — 소스를 공유하는 별도 타깃 2개는 필요하지 않습니다 ([SPEC-0005](../07-기획/SPEC-0005-tenivision-module.md)에서 검증).

```swift
destinations: [.iPhone, .mac],
deploymentTargets: .multiplatform(iOS: "26.0", macOS: "15.0")
```

macOS 하한이 15.0인 것은 `DetectTrajectoriesRequest`가 macOS 15+이기 때문입니다.

**지켜야 할 것:**

- **UIKit·SwiftUI·AppKit을 import하지 않습니다.** 플랫폼 중립 API를 먼저 찾습니다 (`UIDevice` → `ProcessInfo`)
- 플랫폼 전용 API가 불가피하면 `#if os(iOS)`로 **그 함수만** 감쌉니다. 파일 전체를 감싸면 macOS에서 타입이 사라져 CLI가 못 씁니다
- 살아있는 `AVCaptureDevice`를 다루는 코드는 iOS 전용입니다. `AVCaptureDevice.Format`의 `isVideoBinned`·`videoFieldOfView`·`minISO`·`videoMaxZoomFactor` 등이 macOS에 없습니다
- 반대로 **Codable 데이터 모델과 계산식은 반드시 양 플랫폼 공용**으로 둡니다. CLI가 앱이 내보낸 JSON을 읽는 경로이기 때문입니다

`scripts/verify-ios.sh`가 `Projects/*/Project.swift`에서 `.mac`을 선언한 모듈을 찾아 macOS로도 빌드하므로, 이 규약 위반은 게이트에서 걸립니다. 테스트 타깃(`product: .unitTests`)이 있는 모듈은 `build` 대신 `test`를 돌립니다.

`TeniVision`은 **정적 프레임워크**입니다. macOS CLI는 앱 번들이 아니라 프레임워크를 동봉할 자리가 없고 `@rpath`로 찾을 수도 없습니다. 리소스가 없으므로 정적으로 바꿔도 앱이 잃는 것이 없습니다.

### 개발 도구의 외부 의존성

**앱과 `TeniVision`은 의존성 0을 유지합니다.** 외부 패키지는 `TeniTool`에만 붙입니다 — 개발 도구는 앱 크기·ANE·기동 시간과 무관하므로 [D-06](../05-결정/stack/D-06-pose-engine.md)·[D-12](../05-결정/stack/D-12-dependency-injection.md)의 판단이 적용되지 않습니다.

선언은 `ios/Tuist/Package.swift`에, 사용은 `.external(name:)`으로 합니다.

CLI는 **실행 파일 + 라이브러리 두 타깃**입니다. 실행 파일의 심볼은 테스트 번들에서 링크할 수 없으므로(앱과 달리 `bundle_loader`를 쓸 수 없습니다) 로직을 `TeniToolKit`에 두고 실행 파일은 `@main`만 갖습니다.

### 코드 서명

**`DEVELOPMENT_TEAM`은 매니페스트에 둡니다.** Xcode의 Signing & Capabilities에서 팀을 고르면 생성된 `.xcodeproj`에만 기록되고, 다음 `tuist generate`가 덮어씁니다. 매번 다시 고르게 됩니다.

| 설정 | 값 | 대상 |
|---|---|---|
| `DEVELOPMENT_TEAM` | `VW2UR5Y845` (JUNHYEOK LEE) | 앱 타깃만 |
| `CODE_SIGN_STYLE` | `Automatic` | 앱 타깃만 |

**프레임워크와 CLI에는 넣지 않습니다.** `TeniVision`은 정적 프레임워크라 앱에 링크될 뿐 따로 서명되지 않고, `TeniTool`은 로컬에서 돌리는 개발 도구입니다.

게이트는 `CODE_SIGNING_ALLOWED=NO`로 빌드하므로 CI 러너에 인증서가 없어도 통과합니다. **서명이 실제로 되는지는 실기기 빌드에서만 드러납니다** — 게이트가 덮지 못하는 항목입니다.

> 팀 ID는 표시 이름이 아닙니다. `security find-identity -v -p codesigning`으로 인증서를, 프로비저닝 프로필의 `TeamIdentifier`로 ID를 확인합니다.

### 의존성 방향

```
        Application
             │
    ┌────────┼────────┐
Presentation  Data ──→ Network
    │  │       │           │
    │  └──→ Domain ←───────┘
    │          ▲
    │      TeniVision
    │          │
DesignSystem   │
    └────→ Core ←───┘
```

- `Domain`은 아무것도 import하지 않습니다 (Foundation 제외)
- `TeniVision`은 `Domain` 엔티티와 `Core`만 압니다. **UI를 모르므로 macOS CLI에서 재사용됩니다**

> **`VisionKit`이라는 이름을 쓰지 않습니다.** Apple이 같은 이름의 프레임워크(문서 스캐너·`DataScannerViewController`)를 제공하므로 `import VisionKit`이 모호해집니다.
- `Network`는 `Domain`을 모릅니다. DTO만 다루고 매핑은 `Data`가 합니다
- `Presentation` 내 Feature 간 직접 의존은 금지. `Application` 코디네이터를 경유합니다
- 프레임 스트림은 `Presentation`이 `TeniVision`을 직접 씁니다 (TCA 바깥 경로)

## 5.5 전체 파일 구조

```
ios/
├── Tuist/
│   ├── Config.swift
│   └── ProjectDescriptionHelpers/
│       ├── Module.swift               # 모듈 정의 헬퍼
│       └── Dependencies.swift
├── Workspace.swift
├── Projects/
│   ├── App/
│   │   ├── Project.swift
│   │   ├── Sources/
│   │   │   ├── Application/
│   │   │   │   ├── TeniTeniApp.swift
│   │   │   │   ├── AppDelegate.swift
│   │   │   │   └── RootView.swift
│   │   │   ├── DI/
│   │   │   │   ├── AppContainer.swift
│   │   │   │   └── UseCaseFactory.swift
│   │   │   └── Navigation/
│   │   │       └── AppCoordinator.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Info.plist
│   │
│   ├── Features/
│   │   ├── Capture/
│   │   │   ├── Project.swift
│   │   │   ├── Sources/
│   │   │   │   ├── View/
│   │   │   │   │   ├── CaptureView.swift
│   │   │   │   │   ├── MetalCameraView.swift      # UIViewRepresentable → MTKView
│   │   │   │   │   └── CaptureControlBar.swift
│   │   │   │   ├── Reducer/
│   │   │   │   │   ├── CaptureFeature.swift       # @Reducer
│   │   │   │   │   └── CaptureFeature+Effects.swift
│   │   │   │   ├── OverlayState/
│   │   │   │   │   └── OverlayModel.swift         # @Observable, TCA 바깥 60fps 경로
│   │   │   │   ├── Overlay/
│   │   │   │   │   └── GuideOverlay.swift         # SwiftUI. 가이드·경고·각도 라벨
│   │   │   │   └── Camera/
│   │   │   │       ├── CameraSession.swift        # AVCaptureSession 구성
│   │   │   │       ├── FormatSelector.swift       # 120/240fps 포맷 선택
│   │   │   │       ├── FrameRingBuffer.swift      # 소급 저장용 링 버퍼
│   │   │   │       └── ClipRecorder.swift         # AVAssetWriter
│   │   │   └── Tests/
│   │   ├── Analysis/          # 스윙 리플레이, 지표, 피드백
│   │   ├── Session/           # 세션 시작/종료/요약
│   │   ├── Library/           # 저장된 클립 목록
│   │   ├── Progress/          # 진척도 차트
│   │   └── Onboarding/        # 카메라 배치 가이드
│   │
│   ├── Domain/
│   │   ├── Project.swift
│   │   └── Sources/
│   │       ├── Entities/
│   │       │   ├── User.swift
│   │       │   ├── Session.swift
│   │       │   ├── Clip.swift
│   │       │   ├── Swing.swift
│   │       │   ├── SwingPhase.swift
│   │       │   ├── SwingMetrics.swift
│   │       │   ├── PoseFrame.swift
│   │       │   ├── Trajectory.swift
│   │       │   ├── Feedback.swift
│   │       │   └── ReferenceSwing.swift
│   │       ├── UseCases/
│   │       │   ├── StartCaptureSession.swift
│   │       │   ├── DetectSwings.swift
│   │       │   ├── AnalyzeSwing.swift
│   │       │   ├── GenerateFeedback.swift
│   │       │   ├── CompareWithReference.swift
│   │       │   ├── UploadClip.swift
│   │       │   └── FetchProgress.swift
│   │       └── Repositories/          # 프로토콜만
│   │           ├── ClipRepository.swift
│   │           ├── SwingRepository.swift
│   │           ├── SessionRepository.swift
│   │           └── ReferenceRepository.swift
│   │
│   ├── Data/
│   │   ├── Project.swift
│   │   └── Sources/
│   │       ├── Network/
│   │       │   ├── Targets/           # Moya TargetType (D-11)
│   │       │   ├── APIClient.swift
│   │       │   ├── AuthMiddleware.swift
│   │       │   └── UploadService.swift
│   │       ├── Persistence/
│   │       │   ├── Models/            # SwiftData @Model
│   │       │   ├── PoseArchive.swift  # 시계열 파일 직렬화
│   │       │   └── FileStore.swift    # 영상 파일 관리
│   │       └── Repositories/          # 프로토콜 구현체
│   │
│   ├── TeniVision/
│   │   ├── Project.swift
│   │   ├── Sources/
│   │   │   ├── Pipeline/
│   │   │   │   ├── FrameIntake.swift          # 델리게이트 → 3갈래 분기
│   │   │   │   ├── ReadyFrame.swift           # CMReadySampleBuffer 래핑 (Sendable)
│   │   │   │   ├── FrameStream.swift          # AsyncStream 정책 (D-04)
│   │   │   │   └── Downscaler.swift
│   │   │   ├── Pose/
│   │   │   │   ├── PoseEstimator.swift
│   │   │   │   ├── PoseSkeleton.swift
│   │   │   │   ├── OneEuroFilter.swift
│   │   │   │   ├── PoseSmoother.swift
│   │   │   │   └── JointAngle.swift
│   │   │   ├── Render/                        # ★ Metal (D-07)
│   │   │   │   ├── FrameRenderer.swift
│   │   │   │   ├── CameraTexturePass.swift
│   │   │   │   ├── SkeletonPass.swift
│   │   │   │   ├── TrajectoryPass.swift
│   │   │   │   ├── RenderTransform.swift      # 단일 변환 행렬
│   │   │   │   ├── RenderablePose.swift
│   │   │   │   ├── OffscreenRenderer.swift    # 녹화 합성용
│   │   │   │   ├── Shaders.metal
│   │   │   │   └── SkeletonStyle.swift
│   │   │   ├── Ball/
│   │   │   │   ├── BallTracker.swift          # DetectTrajectoriesRequest 래핑
│   │   │   │   └── TrajectoryFitter.swift
│   │   │   ├── Court/
│   │   │   │   ├── CourtDetector.swift
│   │   │   │   └── Homography.swift
│   │   │   ├── Swing/
│   │   │   │   ├── SwingSegmenter.swift
│   │   │   │   ├── SwingClassifier.swift
│   │   │   │   └── PhaseSplitter.swift
│   │   │   └── Metrics/
│   │   │       ├── MetricsCalculator.swift
│   │   │       ├── ScoreEvaluator.swift
│   │   │       ├── RuleEngine.swift
│   │   │       └── DTW.swift
│   │   └── Tests/
│   │       ├── Fixtures/              # 샘플 영상 (Git LFS)
│   │       └── GoldenTests/           # 결정론적 회귀 테스트
│   │
│   ├── MLModels/                      # SwingClassifier.mlpackage 등
│   ├── DesignSystem/
│   └── Core/
│
├── fastlane/
│   ├── Fastfile
│   └── Appfile
├── .swiftlint.yml
├── .swiftformat
├── mise.toml
└── Makefile                           # make bootstrap / generate / test
```

## 5.6 테스트 전략

| 종류 | 대상 | 도구 |
|---|---|---|
| **골든 테스트** | TeniVision — 고정 샘플 영상 입력 → 검출 결과 검증 | Swift Testing |
| 단위 테스트 | Domain UseCase, RuleEngine, DTW, OneEuroFilter | Swift Testing |
| 스냅샷 테스트 | 오버레이 렌더링 결과 | `OffscreenRenderer` 출력 비교 (⬜ 검토) |
| 통합 테스트 | Data 레이어 (mock 서버) | XCTest |
| UI 테스트 | 핵심 플로우 1~2개만 | XCUITest |

**골든 테스트가 이 프로젝트의 핵심입니다.** 샘플 영상 10개에 대해 "스윙 개수, 유형, 임팩트 프레임 인덱스, 주요 각도"를 스냅샷으로 고정하면, 파이프라인을 수정할 때마다 회귀를 즉시 잡을 수 있습니다. 튜닝이 잦은 영역이라 이게 없으면 개선인지 퇴보인지 알 수 없습니다.

## 관련 문서

- [시스템 아키텍처](../02-설계/ARCHITECTURE.md)
- [스켈레톤 오버레이](../02-설계/SKELETON-OVERLAY.md)
- [저장소 구조](../03-기술스택/REPOSITORY.md)
- [결정 현황](../05-결정/DECISION-LOG.md)

---

[← 문서 허브](../INDEX.md)
