---
title: "동시성과 상태 설계"
aliases: ["동시성", "Concurrency", "상태 머신"]
tags:
  - 문서유형/설계
  - 영역/iOS
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 06. 동시성과 상태 설계

Swift 6 strict concurrency 아래에서 격리 도메인을 어떻게 나눌지, 그리고 촬영 화면의 에러·열화 상태를 어떻게 다룰지 정의합니다.

이걸 정하지 않고 코드를 쓰면 나중에 전면 수정입니다.

## 6.1 원칙

1. **프레임은 한 시점에 한 소유자만 갖는다.** 공유하지 않고 변환해서 넘긴다
2. **델리게이트 콜백은 즉시 반환한다.** 버퍼를 붙들면 캡처 풀이 고갈돼 프레임이 드롭된다
3. **순서가 중요한 처리는 actor가 아니라 단일 Task로 한다.** actor는 재진입되기 때문
4. **`@unchecked Sendable`을 쓰지 않는다.** iOS 26의 `Sendable` 타입으로 해결한다

## 6.2 격리 도메인 배치

| 컴포넌트 | 격리 | 근거 |
|---|---|---|
| `CaptureView`, TCA `Store` | `@MainActor` | UI |
| `FrameRenderer` (MTKView delegate) | `@MainActor` | `draw(in:)`이 메인에서 호출됨 |
| `OverlayModel` (`@Observable`) | `@MainActor` | 뷰가 직접 구독. [D-03](../05-결정/stack/D-03-architecture-pattern.md) TCA 바깥 60fps 경로 |
| `CameraSession` | `actor` | 세션 구성이 여러 곳에서 호출됨. 내부적으로 전용 `DispatchQueue`에 위임 |
| `captureOutput(_:didOutput:from:)` | `nonisolated` + 전용 `DispatchQueue` | AVFoundation이 지정 큐에서 호출 |
| `TrajectoryAnalyzer` | **단일 `Task` + `AsyncStream`** | 프레임 순서가 절대적 (6.4절) |
| `PoseAnalyzer` | **단일 `Task` + `AsyncStream`** | 스무딩·세그멘테이션이 상태를 누적 |
| `ClipRecorder` | `actor` | 링 버퍼와 `AVAssetWriter` 상태 보호 |
| `Domain` UseCase, `VisionKit` 순수 계산 | `nonisolated` | 상태 없음 |

```
                    ┌─ @MainActor ─────────────────────┐
                    │  CaptureView / TCA Store         │
                    │  FrameRenderer (MTKView)         │
                    │  OverlayModel (@Observable)      │
                    └──────────▲───────────▲───────────┘
                               │ 텍스처    │ 포즈
  ┌── captureQueue (nonisolated) ─────────┼───────────┐
  │  captureOutput                        │           │
  │    ├─→ Metal 텍스처 변환 ──────────────┘           │
  │    ├─→ 궤적 스트림 yield ──→ [Task] TrajectoryAnalyzer
  │    ├─→ 포즈 스트림 yield  ──→ [Task] PoseAnalyzer ─┘
  │    └─→ actor ClipRecorder (링 버퍼)                │
  └────────────────────────────────────────────────────┘
                               │
                       actor CameraSession
                       (구성 · 시작 · 정지)
```

## 6.3 프레임 소유권

### `CMReadySampleBuffer` — iOS 26이 주는 것

[D-01](../05-결정/stack/D-01-deployment-target.md)에서 iOS 26을 확정한 덕에 `CMReadySampleBuffer`를 쓸 수 있습니다.

| | `CMSampleBuffer` | `CMReadySampleBuffer` |
|---|---|---|
| 가용 | 이전부터 | **iOS 26.0+** |
| 타입 | 참조 타입 (CF) | **`struct`, `Sendable`** |
| 콘텐츠 | 런타임 검사 | **제네릭으로 타입 고정** |

델리게이트에서 받은 `CMSampleBuffer`를 경계에서 한 번 감싸면, 이후로는 `@unchecked Sendable` 없이 격리 도메인을 넘길 수 있습니다.

```swift
// VisionKit/Pipeline/FrameIntake.swift
nonisolated func captureOutput(_ output: AVCaptureOutput,
                               didOutput sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
    // 콜백은 즉시 반환한다. 여기서 무거운 일을 하면 캡처 풀이 고갈된다
    guard let ready = CMReadySampleBuffer<CMSampleBuffer.PixelBufferContent>(
        unsafeWithPixelBuffer: sampleBuffer
    ) else { return }

    let seq = sequence.wrappingIncrement()

    // ① 렌더 — IOSurface 공유. 픽셀 복사 없음
    textureCache.makeTexture(from: ready) { [renderQueue] texture in
        renderQueue.submit(texture, at: ready.presentationTimeStamp)
    }

    // ② 궤적 — 전 프레임. 순서 보존 필수
    trajectoryContinuation.yield(ready)

    // ③ 포즈 — 60fps로 데시메이션 (120fps일 때 2프레임에 1개)
    if seq % UInt64(decimation) == 0 {
        poseContinuation.yield(ready)
    }

    // ④ 녹화 링 버퍼
    Task { await clipRecorder.enqueue(ready) }
}
```

### 규칙

- **픽셀을 복사하지 않는다.** Metal 텍스처는 `CVMetalTextureCache`로 IOSurface를 공유한다
- **분석용 다운스케일은 소비자 쪽에서 한다.** 인테이크에서 하면 콜백이 길어진다
- `alwaysDiscardsLateVideoFrames = true` — 밀리면 버린다. [D-04](../05-결정/stack/D-04-concurrency.md)의 오버레이 정책과 일치한다

## 6.4 스트림 분리 구현

[D-04](../05-결정/stack/D-04-concurrency.md)에서 확정한 오버레이/분석 스트림 분리의 구체 형태입니다.

```swift
// 궤적 — 연속성 우선. 버리지 않는다
let (trajectoryStream, trajectoryContinuation) = AsyncStream.makeStream(
    of: ReadyFrame.self,
    bufferingPolicy: .bufferingOldest(8)     // 순서 보존, 상한으로 폭주 차단
)

// 포즈 — 최신성 우선. 밀리면 버린다
let (poseStream, poseContinuation) = AsyncStream.makeStream(
    of: ReadyFrame.self,
    bufferingPolicy: .bufferingNewest(1)
)
```

### 왜 actor가 아니라 단일 Task인가

`DetectTrajectoriesRequest`는 **연속 프레임을 순서대로** 받아야 포물선을 찾습니다. actor로 만들면 `await` 지점에서 다른 호출이 끼어들 수 있어(재진입) 순서 보장이 코드에 드러나지 않습니다.

단일 Task가 스트림을 소비하면 **순차성이 구조로 보장**되고 의도도 명확합니다.

```swift
// VisionKit/Ball/TrajectoryAnalyzer.swift
func run(_ frames: AsyncStream<ReadyFrame>) -> AsyncStream<TrajectoryEvent> {
    AsyncStream { continuation in
        let task = Task(priority: .userInitiated) {
            var request = DetectTrajectoriesRequest(
                trajectoryLength: 5,
                frameAnalysisSpacing: .zero
            )
            request.objectMinimumNormalizedRadius = 0.002
            request.objectMaximumNormalizedRadius = 0.015

            for await frame in frames {          // ← 순차 보장
                guard !Task.isCancelled else { break }
                let observations = try? await request.perform(on: frame.pixelBuffer)
                for o in observations ?? [] {
                    continuation.yield(.detected(o, at: frame.timestamp))
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

파라미터 값의 근거는 [촬영 프로토콜 5.4](CAPTURE-PROTOCOL.md#54-궤적-검출-파라미터-초기값)에 있습니다.

### TCA 경계

[D-03](../05-결정/stack/D-03-architecture-pattern.md)의 필수 규칙 — **60fps는 Store를 거치지 않습니다.**

| 이벤트 | 빈도 | 경로 |
|---|---|---|
| 포즈 프레임 | 60fps | `PoseAnalyzer` → `@MainActor OverlayModel` (직접) |
| 궤적 점 | 120fps | `TrajectoryAnalyzer` → `OverlayModel` (직접) |
| 스윙 검출 | 초당 1회 미만 | → TCA `Effect` → `.swingDetected` |
| 세션 상태·열화 | 드묾 | → TCA `Effect` |

## 6.5 상태 머신

### 상태 정의

```swift
// Features/Capture/Reducer/CaptureFeature.swift
@Reducer
struct CaptureFeature {
    @ObservableState
    struct State: Equatable {
        var status: Status = .idle
        var degradations: Set<Degradation> = []   // status와 직교
        var quality: CaptureQuality = .precise    // 120 / 60 — 사용자 선택
        var effectiveFPS: Int = 120               // 실제 적용값. 강등되면 달라진다
    }

    enum Status: Equatable {
        case idle
        case requestingPermission
        case permissionDenied(PermissionKind)     // 복구: 설정 앱 유도
        case configuring
        case ready
        case recording(SessionID)
        case interrupted(InterruptionReason)      // 복구: 자동
        case failed(CaptureError)
    }

    /// 열화는 **중단이 아니다.** 촬영을 계속하되 품질을 낮추고 알린다
    enum Degradation: Hashable {
        case thermal(AVCaptureDevice.SystemPressureState.Level)
        case fpsDowngraded(from: Int, to: Int)
        case lowLight                              // ISO 상한 도달
        case shake                                 // 궤적 기능 자동 비활성화
        case lowStorage(remainingMB: Int)
    }
}
```

**핵심은 `degradations`를 `status`와 분리한 것**입니다. 발열·조명·흔들림은 촬영을 멈출 이유가 아니라 사용자에게 알리고 품질을 조정할 사유입니다. 이걸 `status`에 섞으면 "발열 중이면서 녹화 중"을 표현할 수 없습니다.

### 전이

| 전이 | 트리거 | 복구 |
|---|---|---|
| `idle → requestingPermission` | 화면 진입 | — |
| `→ permissionDenied` | 사용자 거부 | 설정 앱 링크. `applicationDidBecomeActive`에서 재확인 |
| `→ configuring → ready` | 권한 승인 | — |
| `ready → recording` | 촬영 시작 | — |
| `* → interrupted` | `wasInterruptedNotification` | `interruptionEndedNotification`에서 자동 복귀 |
| `* → failed` | `runtimeErrorNotification` | 세션 재구성 1회 재시도 |
| `recording → ready` | 촬영 종료 | — |

인터럽션 사유(전화 수신, 다른 앱의 카메라 점유, **시스템 압력 초과**)는 `AVCaptureSession.InterruptionReason`으로 구분해 사용자에게 다르게 안내합니다.

## 6.6 열화 대응

### 시스템 압력 — `AVCaptureDevice.SystemPressureState`

`ProcessInfo.thermalState`보다 **캡처 시스템에 특화된 신호**입니다. `systemPressureState`를 KVO로 관찰합니다.

> 시스템 압력이 과도해지면 **캡처 시스템이 자동으로 세션을 종료**합니다. 그 전에 대응해야 합니다.

| 압력 수준 | 조치 | 사용자 고지 |
|---|---|---|
| `.nominal` / `.fair` | 유지 | 없음 |
| `.serious` | `frameAnalysisSpacing` 증가, 포즈 데시메이션 강화 | 없음 |
| `.critical` | **fps 120 → 60 강등** | **필수** |
| `.shutdown` | 시스템이 세션 중단 | `interrupted` 처리 |

### ⚠️ fps 강등 시 반드시 할 것

사용자가 **정밀(120fps)을 선택했는데 시스템이 60으로 낮추면**:

1. `degradations`에 `.fpsDowngraded(from: 120, to: 60)` 추가 → UI에 표시
2. **해당 클립의 `captureFPS`를 실제값 60으로 기록** ([촬영 프로토콜 5.2](CAPTURE-PROTOCOL.md#52-캡처-포맷))
3. 압력이 `.fair` 이하로 회복되면 원래 설정으로 복귀하고 그 시점도 기록

사용자가 고른 값과 실제 적용값이 다를 수 있으므로 **`quality`(선택)와 `effectiveFPS`(실제)를 분리**해 들고 있습니다. 이걸 섞으면 나중에 세션 비교가 무의미해집니다.

### 저장 공간

| 시점 | 조치 |
|---|---|
| 녹화 시작 전 | 여유 < 1 GB이면 시작 차단 + 정리 안내 |
| 녹화 중 | 여유 < 500 MB이면 `.lowStorage` 추가, < 200 MB이면 정상 종료 |

120fps는 60fps의 2배를 씁니다. 사용자가 정밀 모드를 선택할 때 예상 사용량을 함께 보여줍니다.

### 흔들림

`CMMotionManager`로 진동을 측정해 임계를 넘으면 `.shake`를 추가하고 **궤적 기능을 자동 비활성화**합니다. `DetectTrajectoriesRequest`는 고정 카메라가 전제라 튜닝으로 해결되지 않습니다 ([촬영 프로토콜 5.6](CAPTURE-PROTOCOL.md#56-프레이밍-가이드-앱-ui)).

조용히 실패하지 않고 **이유를 표시하는 것**이 중요합니다.

## 6.7 단위·좌표 규약

코드 전반에서 지킵니다.

| 대상 | 규약 |
|---|---|
| 시각 | `CMTime` (프레임 식별·동기화). 도메인 경계 밖에서만 `TimeInterval` |
| 각도 | 계산은 **라디안**, 저장·표시는 **도(°)**. 변환은 경계에서 한 번만 |
| 좌표 | Vision 정규화 좌표(0~1, 좌하단 원점)를 렌더 직전까지 유지 ([스켈레톤 오버레이 4.3](SKELETON-OVERLAY.md#43-좌표-변환--단일-변환-행렬)) |
| 길이 | 미터 |
| 속도 | 내부 m/s, 표시 km/h |
| 프레임 식별 | 단조 증가 `UInt64` sequence + `CMTime` 병행 |

## 6.8 Phase 0 검증 항목

- [ ] `CMReadySampleBuffer`로 프레임을 넘길 때 strict concurrency 경고가 0인가
- [ ] 델리게이트 콜백 소요 시간이 1ms 미만인가 (버퍼 풀 고갈 방지)
- [ ] 120fps에서 궤적 스트림이 프레임을 빠뜨리지 않는가
- [ ] 포즈 스트림이 밀릴 때 오래된 프레임을 버리는가 (메모리 안정)
- [ ] 발열 시 `.critical`에서 fps 강등이 동작하고 `captureFPS`가 실제값으로 기록되는가
- [ ] 전화 수신 후 세션이 자동 복귀하는가

## 관련 문서

- [촬영 프로토콜](CAPTURE-PROTOCOL.md)
- [스켈레톤 오버레이](SKELETON-OVERLAY.md)
- [시스템 아키텍처](ARCHITECTURE.md)
- [D-03 아키텍처 패턴](../05-결정/stack/D-03-architecture-pattern.md)
- [D-04 비동기 / 상태 관리](../05-결정/stack/D-04-concurrency.md)

---

[← 문서 허브](../INDEX.md)
