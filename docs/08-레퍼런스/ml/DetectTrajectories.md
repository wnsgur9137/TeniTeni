---
title: "DetectTrajectoriesRequest API"
aliases: ["DetectTrajectoriesRequest", "궤적 검출 API"]
tags:
  - 문서유형/레퍼런스
  - 영역/비전
researched: 2026-09-11
created: 2026-09-11
updated: 2026-09-11
status: active
---

# DetectTrajectoriesRequest API

> Phase 0 게이트의 검증 대상. 이 API가 무엇을 주고 무엇을 안 주는지가 0-C 도구의 설계를 결정한다.

이슈 [#7](https://github.com/wnsgur9137/TeniTeni/issues/7) 착수 전 조사. 출처는 Apple 공식 문서이며 2026-09-11 기준이다.

## 1. 시그니처

```swift
final class DetectTrajectoriesRequest   // struct가 아니다
```

iOS 18.0+ / **macOS 15.0+**. 0-C CLI의 전제가 성립한다.

준수 프로토콜 중 중요한 둘:

| 프로토콜 | 의미 |
|---|---|
| `StatefulRequest` | **연속 프레임에서 상태를 누적한다.** 인스턴스를 재사용해야 한다 |
| `Sendable` | 격리 도메인 간 전달 가능 |

### 생성

```swift
init(trajectoryLength: Int,
     _ revision: DetectTrajectoriesRequest.Revision? = nil,
     frameAnalysisSpacing: CMTime? = nil)
```

**`revision`이 무명 파라미터다.** 두 번째 인자에 레이블이 없다.

- `trajectoryLength` — 포물선 판정에 필요한 점 개수. **최소 5**
- `frameAnalysisSpacing` — 분석 간격. 기본값 `nil`이면 **모든 프레임**을 분석한다

### 수행

```swift
func perform(on sampleBuffer: CMSampleBuffer,
             orientation: CGImagePropertyOrientation?) async throws -> Self.Result
```

`async throws`다. `CGImage`·`CVPixelBuffer`·`URL`·`Data`·`CIImage` 오버로드도 있지만, **`CMSampleBuffer`를 써야 한다** — 타임스탬프가 붙어 있어야 `timeRange`가 나온다.

## 2. 관측

```swift
struct TrajectoryObservation   // 이쪽은 struct
```

| 멤버 | 내용 |
|---|---|
| `detectedPoints: [NormalizedPoint]` | 실제 검출된 중심점들. 허용 오차 안에서 이상적 궤적과 다를 수 있다 |
| `projectedPoints` | 검출점에서 계산한 이상적 궤적 |
| `equationCoefficients` | 포물선 계수 |
| `movingAverageRadius` | **추적 물체의 이동 평균 반지름** |

### ⚠️ `timeRange`는 타입 고유 멤버가 아니다

Apple 문서의 `TrajectoryObservation` 페이지 "Inspecting an observation" 목록에 **`timeRange`가 없다.** 없는 줄 알고 설계하면 [촬영 프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md)의 `startFrame`·`durationSec`을 직접 세야 한다.

실제로는 `VisionObservation` 프로토콜에 있다.

```swift
var timeRange: CMTimeRange? { get }
```

> 이미지 버퍼 시퀀스를 평가할 때 이 속성으로 각 관측의 **시작 시각과 지속 시간**을 얻는다. 요청이 시간 범위를 지원하지 않거나 알 수 없으면 `nil`.

**타입 페이지만 보면 놓친다.** 준수 프로토콜을 따라가야 전체 멤버가 보인다.

같은 이유로 `VisionObservation`에서 오는 것들:

| 멤버 | 쓰임 |
|---|---|
| `uuid` | **같은 궤적의 중복 보고를 식별**한다. 프레임마다 갱신된 관측이 나오므로 이게 없으면 한 타구를 여러 번 센다 |
| `confidence` | 검출 신뢰도 |
| `originatingRequestDescriptor` | 어떤 요청·리비전이 만들었는가 |

## 3. 파라미터

| 속성 | 내용 |
|---|---|
| `trajectoryLength` | 궤적 확정에 필요한 점 개수 (최소 5) |
| `objectMinimumNormalizedRadius` | 검출 대상 최소 크기 |
| `objectMaximumNormalizedRadius` | 최대 크기 |
| `targetFrameTime` | 목표 프레임 처리 시간 |
| `frameAnalysisSpacing` | `StatefulRequest`에서 옴. 최대 처리율의 역수 |
| `minimumLatencyFrameCount` | **관측을 내기 전 처리해야 하는 최소 프레임 수** |

`minimumLatencyFrameCount`가 0-D 실시간 파이프라인의 지연 예산에 들어간다. 0-C에서는 오프라인이라 문제가 없지만, 값을 기록해 두면 0-D 설계에 쓸 수 있다.

## 4. 0-C 설계에 미치는 것

| 확인 사항 | 결론 |
|---|---|
| macOS에서 동작하는가 | ✅ macOS 15.0+ |
| 프레임 시각을 얻는가 | ✅ `timeRange` — 단, `CMSampleBuffer`로 먹여야 한다 |
| 중복 궤적을 가리는가 | ✅ `uuid` |
| 인스턴스를 재사용해야 하는가 | ✅ `StatefulRequest` — 프레임마다 새로 만들면 상태가 날아간다 |
| 공 크기를 알려주는가 | ✅ `movingAverageRadius` — 화각 실측 없이 직접 비교 가능 |

**`teni analyze`는 `AVAssetReader`로 `CMSampleBuffer`를 순차로 읽어 하나의 요청 인스턴스에 먹인다.** `CGImage`로 변환하면 타임스탬프가 사라져 `timeRange`가 `nil`이 된다.

## 6. 실측 (2026-09-11, `teni analyze` 최초 실행)

`teni synth` 합성 영상(1920×1080, 120fps, 6m, 화각 70°, 공 지름 15.31px)으로 확인했다.

### 5절의 미확인 항목이 해소됐다

| 항목 | 결과 |
|---|---|
| `timeRange`가 무엇을 담는가 | **궤적 시작 시점.** startFrame이 정답 임팩트와 차이 **0** (3개 전부) |
| `uuid`가 수명 동안 유지되는가 | ✅ 타구 3개 → 궤적 3개. 중복 보고가 하나로 묶였다 |
| 검출되는가 | ✅ 1/1000s에서 **검출률 100%, 오검출 0** |

`timeRange`가 정확하므로 프레임을 직접 셀 필요가 없다.

### ⚠️ `movingAverageRadius`는 공 크기가 아니다

노출을 바꿔가며 쟀다. 가로 해상도(1920) 기준으로 환산한 값이다.

| 노출 | 블러 (px) | **검출 지름** | 공만 | 공+블러 | 대각선 |
|---|---|---|---|---|---|
| 1/1000 s | 5.55 | **27.66** | 15.31 | 20.86 | 25.88 |
| 1/500 s | 11.72 | **32.01** | 15.31 | 27.03 | 31.06 |
| 1/250 s | 24.41 | **39.96** | 15.31 | 39.72 | 42.57 |

**노출이 길수록 커집니다.** 공은 그대로인데 값이 27.66 → 39.96으로 변합니다. 블러 스트릭을 감싸는 **바운딩 원**의 반지름이고, 대각선 `√((공+블러)² + 공²)`에 가깝습니다.

정규화 기준은 **가로**입니다. 1920×1920 정사각 영상으로 확인했습니다 — 세로 기준이었다면 비율이 달라졌어야 하는데 1.79배로 같았습니다.

**이 값을 공 크기 검증에 쓰면 안 됩니다.** 1/1000s에서도 1.8배입니다.

### 파라미터 범위 점검

[프로토콜 5.4](../../02-설계/CAPTURE-PROTOCOL.md)의 초기값을 위 실측과 대조했습니다.

| 파라미터 | 값 | 픽셀 지름 | 판정 |
|---|---|---|---|
| `objectMinimumNormalizedRadius` | 0.002 | 7.7 px | ✅ 여유 |
| `objectMaximumNormalizedRadius` | 0.015 | 57.6 px | ✅ 1/250s의 39.96px도 담는다 |

**상한이 "모션 블러 여유 포함"이라 적힌 것이 맞는 방향이었습니다.** 블러가 반지름을 키우므로 공 크기만으로 잡으면 긴 노출에서 검출이 끊깁니다.

## 5. 확인하지 못한 것

- **실영상 검출률** — 6절은 합성 영상이다. 배경이 균일하고 공만 움직이므로 실영상보다 쉽다. **게이트 판정은 실영상이어야 한다** ([프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md))
- **`minimumLatencyFrameCount` 실측** — 0-D 지연 예산에 필요하다. 오프라인에서는 문제가 없어 재지 않았다
- **`confidence`의 의미** — 합성 영상에서 전부 1.00이 나왔다. 실영상에서 어떻게 분포하는지 모른다
- **`trajectoryLength`를 늘렸을 때** — 5(최소)로만 시험했다. 검출점이 정확히 5개만 모였으므로 6 이상이면 검출이 끊길 수 있다. #9의 스윕 대상

## 관련 문서

- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md) — 파라미터 초기값
- [촬영 프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md) — 기록 포맷
- [모션 블러와 공 추적](MotionBlur.md)
- [TrackNet](TrackNet.md) — 게이트 미달 시 대안
- [레퍼런스 허브](../INDEX.md)

## 출처

- [DetectTrajectoriesRequest](https://developer.apple.com/documentation/vision/detecttrajectoriesrequest)
- [TrajectoryObservation](https://developer.apple.com/documentation/vision/trajectoryobservation)
- [VisionObservation](https://developer.apple.com/documentation/vision/visionobservation)
- [StatefulRequest](https://developer.apple.com/documentation/vision/statefulrequest)

---

[← 문서 허브](../../INDEX.md)
