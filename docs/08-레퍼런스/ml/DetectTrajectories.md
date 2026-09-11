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

## 5. 확인하지 못한 것

- **`timeRange`가 실제로 무엇을 담는가** — 문서는 "시작 시각과 지속 시간"이라고만 한다. 궤적이 시작된 시점인지 관측이 보고된 시점인지는 실행해 봐야 안다. `teni synth`의 정답과 대조하면 판정된다
- **`uuid`가 궤적 수명 동안 유지되는가** — 프레임마다 갱신될 때 같은 값인지 확인 필요
- **검출률** — 이 조사는 API 표면만 본 것이다. 실제 성능이 Phase 0 게이트의 판정 대상이다

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
