---
title: "iOS 기술 스택"
aliases: ["iOS 기술 스택", "iOS Stack"]
tags:
  - 문서유형/설계
  - 영역/iOS
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 05. iOS 기술 스택

> 이 문서의 모든 항목은 [stack-decisions.md](../05-결정/DECISION-LOG.md)에서 순차적으로 확정합니다.
> 현재 대부분 🟡 잠정 상태입니다.

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
| 언어 | Swift 6.x (strict concurrency) | 🟡 | — |
| 최소 타깃 | **iOS 26.0** | ✅ | [D-01](../05-결정/stack/D-01-deployment-target.md)에서 확정 |
| UI | SwiftUI + `@Observable` | ✅ | [D-02](../05-결정/stack/D-02-ui-framework.md)에서 확정 |
| 아키텍처 | Clean Architecture + **TCA** | ✅ | [D-03](../05-결정/stack/D-03-architecture-pattern.md)에서 확정 |
| 비동기 | Swift Concurrency + TCA Effect | ✅ | [D-04](../05-결정/stack/D-04-concurrency.md)에서 확정 |
| 카메라 | AVFoundation | ✅ | — |
| 비전 | Vision (신규 Swift API) + Core ML | ✅ | [D-06](../05-결정/stack/D-06-pose-engine.md)에서 확정 |
| 오버레이 렌더 | **Metal** (프리뷰 직접 렌더) | ✅ | [D-07](../05-결정/stack/D-07-overlay-rendering.md)에서 확정 |
| 녹화 | AVAssetWriter | ✅ | — |
| 로컬 DB | SwiftData | ⬜ | GRDB, Realm, Core Data |
| 시계열 저장 | 파일 (Protobuf) | ⬜ | JSON+gzip, FlatBuffers |
| 네트워크 | URLSession + swift-openapi-generator | 🟡 | Alamofire, Moya |
| DI | swift-dependencies (TCA 내장) | 🟡 | D-03이 좁힘. D-12에서 확인 |
| 모듈 빌드 | Tuist 4 | ✅ | [D-05](../05-결정/stack/D-05-module-tooling.md)에서 확정 |
| 수치 연산 | Accelerate / simd | ✅ | — |
| 로깅 | OSLog | 🟡 | swift-log |
| 크래시/분석 | Firebase Crashlytics | ⬜ | Sentry, TelemetryDeck |
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
| 카메라 프리뷰 | `UIViewRepresentable` → `AVCaptureVideoPreviewLayer` (D-07에서 `MTKView`로 전환 가능) |
| 스켈레톤·궤적 오버레이 | SwiftUI `Canvas` |
| 그 외 전 화면 | SwiftUI |
| 상태 | `@Observable` |

**RxSwift는 도입하지 않습니다.** UI 프레임워크와 무관한 별개 사안으로 D-04에서 확정하지만, 방향은 정해져 있습니다 — 비디오 프레임 파이프라인은 분석이 밀릴 때 프레임을 버려야 하는데(백프레셔) Rx의 기본 동작은 버퍼링이라 메모리가 터집니다.

### 네트워크: swift-openapi-generator

🟡 **잠정** — Apple 공식 도구

FastAPI가 OpenAPI 스펙을 자동 생성하고, 그 스펙에서 Swift 클라이언트 코드를 자동 생성합니다. **서버-클라이언트 계약 불일치를 컴파일 타임에 잡을 수 있습니다.** 1인 개발에서 이 가치는 큽니다.

Alamofire는 이 프로젝트에서 필요한 기능(재시도, 멀티파트)이 대부분 `URLSession`으로 충분하므로 제외 검토.

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
VisionKit (TCA 바깥)
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
    ├── App/                           # 앱 진입점, DI Composition Root
    ├── Features/                      # 화면 단위 모듈
    │   ├── Capture/
    │   ├── Analysis/
    │   ├── Session/
    │   ├── Library/
    │   ├── Progress/
    │   └── Onboarding/
    ├── Domain/                        # 순수 Swift, 의존성 0
    ├── Data/                          # 네트워크 / 영속성 / 리포지토리 구현
    ├── VisionKit/                     # 분석 엔진 (UIKit 의존 없음)
    ├── MLModels/                      # .mlpackage + 로더 (Git LFS)
    ├── DesignSystem/                  # 컬러, 타이포, 공용 컴포넌트
    └── Core/                          # Logger, Extensions, 공용 유틸
```

### 의존성 방향

```
App → Features → Domain ← Data
              ↘         ↗
               VisionKit
        Features → DesignSystem → Core
        Data, VisionKit → Core
```

- `Domain`은 아무것도 import하지 않습니다 (Foundation 제외)
- `VisionKit`은 `Domain`의 엔티티만 알고 UI는 모릅니다
- `Features` 간 직접 의존은 금지. 필요하면 `App`의 코디네이터를 경유합니다

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
│   │   │   │   │   ├── CameraPreview.swift        # UIViewRepresentable
│   │   │   │   │   └── CaptureControlBar.swift
│   │   │   │   ├── ViewModel/
│   │   │   │   │   └── CaptureViewModel.swift
│   │   │   │   ├── Overlay/
│   │   │   │   │   ├── SkeletonOverlay.swift
│   │   │   │   │   ├── TrajectoryOverlay.swift
│   │   │   │   │   ├── GuideOverlay.swift
│   │   │   │   │   ├── PoseCoordinateMapper.swift
│   │   │   │   │   ├── RenderablePose.swift
│   │   │   │   │   └── SkeletonStyle.swift
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
│   │       │   ├── Generated/         # swift-openapi-generator 산출물
│   │       │   ├── APIClient.swift
│   │       │   ├── AuthMiddleware.swift
│   │       │   └── UploadService.swift
│   │       ├── Persistence/
│   │       │   ├── Models/            # SwiftData @Model
│   │       │   ├── PoseArchive.swift  # 시계열 파일 직렬화
│   │       │   └── FileStore.swift    # 영상 파일 관리
│   │       └── Repositories/          # 프로토콜 구현체
│   │
│   ├── VisionKit/
│   │   ├── Project.swift
│   │   ├── Sources/
│   │   │   ├── Pipeline/
│   │   │   │   ├── FrameProcessor.swift
│   │   │   │   ├── FrameStream.swift          # AsyncStream 파이프라인
│   │   │   │   └── Downscaler.swift
│   │   │   ├── Pose/
│   │   │   │   ├── PoseEstimator.swift
│   │   │   │   ├── PoseSkeleton.swift
│   │   │   │   ├── OneEuroFilter.swift
│   │   │   │   ├── PoseSmoother.swift
│   │   │   │   └── JointAngle.swift
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
| **골든 테스트** | VisionKit — 고정 샘플 영상 입력 → 검출 결과 검증 | Swift Testing |
| 단위 테스트 | Domain UseCase, RuleEngine, DTW, OneEuroFilter | Swift Testing |
| 스냅샷 테스트 | 오버레이 렌더링 결과 | swift-snapshot-testing (⬜ 검토) |
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
