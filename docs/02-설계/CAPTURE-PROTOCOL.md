---
title: "촬영 프로토콜"
aliases: ["촬영 프로토콜", "Capture Protocol", "카메라 스펙"]
tags:
  - 문서유형/설계
  - 영역/비전
  - 영역/제품
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 05. 촬영 프로토콜

카메라 배치·포맷·노출 스펙과 **Phase 0 게이트 측정 방법**을 정의합니다.

이 문서가 없으면 `DetectTrajectoriesRequest`의 파라미터를 정할 수 없고, 게이트("궤적 검출률 70%")를 판정할 수도 없습니다.

## 5.1 카메라 배치

| 항목 | 스펙 | 허용 범위 |
|---|---|---|
| **각도** | 측면 (side-on) | 코트 장축에 수직 ±10° |
| **거리** | 6 m | 5 ~ 8 m |
| **높이** | 1.1 m (허리) | 0.9 ~ 1.3 m |
| **방향** | 가로 (landscape) | 고정 |
| **거치** | 삼각대 필수 | — |

### 왜 측면인가

궤적 검출이 결정합니다.

| 각도 | 공의 화면상 움직임 | 궤적 검출 |
|---|---|---|
| **측면** | 프레임을 가로로 가로지름, 겉보기 크기 일정 | ✅ 깨끗한 포물선 |
| 후면 | 카메라에서 멀어짐 → 짧은 수직선으로 압축 | ❌ 이미지 평면에 포물선이 안 그려짐 |
| 정면 | 서브 시 선수가 등을 보임, 코트를 막음 | ❌ |

`DetectTrajectoriesRequest`는 **포물선 궤적**을 찾습니다. 깊이 방향 운동은 원리적으로 검출되지 않습니다.

측면에서 얻는 지표: `kneeFlexion`, `contactPointHeight` / `contactPointDepth`, `elbowAngleAtImpact`, `weightTransfer`, `followThroughAngle`, 스윙 경로(low-to-high).

**측면에서 얻지 못하는 지표**: `hipShoulderSeparation`(X-Factor). 어깨-골반 회전차는 측면 투영에서 정확히 나오지 않습니다. → **v2에서 `DetectHumanBodyPose3DRequest`로 확보**합니다 ([01. 제품 개요](../01-제품/PRODUCT-OVERVIEW.md) 검토 대상 참고).

### 왜 6m인가

공 크기가 상한을, 사람 크기가 하한을 결정합니다. iPhone 광각 수평 화각 약 70°, 1080p 기준입니다.

| 거리 | 프레임 폭 | 공 지름 | 선수 높이 비율 | 판정 |
|---|---|---|---|---|
| 5 m | 7.0 m | 18 px | 45 % | ✅ |
| **6 m** | **8.4 m** | **15 px** | **38 %** | ✅ **권장** |
| 8 m | 11.2 m | 12 px | 28 % | ✅ 하한 |
| 10 m | 14.0 m | 9 px | 23 % | ⚠️ 위험 |
| 12 m | 16.5 m | 8 px | 19 % | ❌ |

6 m에서 프레임 폭 8.4 m는 단식 코트 폭과 비슷합니다. 시속 100 km 기준 공이 프레임을 가로지르는 데 **0.30초**가 걸리므로 120 fps에서 36프레임, 60 fps에서 18프레임을 확보합니다 (`trajectoryLength` 최소값 5).

> ⚠️ 위 수치는 화각 70° 가정에 기반한 **계산값**입니다. Phase 0에서 실기기로 검증해 보정합니다.

### 왜 1.1m인가

광축을 신체 중심(골반 약 0.95 m) 근처에 두면 **상·하체의 원근 왜곡이 대칭**이 되어 관절 각도 오차가 최소화됩니다. 눈높이로 올리면 하체가, 낮추면 상체가 왜곡됩니다.

6 m 거리에서 세로 화각이 4.6 m이므로 지면부터 약 4.5 m까지 들어옵니다. 서브 임팩트(약 2.7 m)도 여유 있게 포함됩니다.

## 5.2 캡처 포맷

### 프레임레이트 — 사용자 선택

| 설정 | 표시 | 궤적 정확도 | 비용 |
|---|---|---|---|
| **120 fps** | **정밀 (권장)** | 프레임 간 공 이동 54 px | 발열·배터리·용량 2배 |
| 60 fps | 표준 | 프레임 간 공 이동 107 px | 기본 |

**기본값은 120 fps**이며, 기기가 지원하지 않으면 60 fps로 자동 설정하고 선택지를 비활성화합니다.

UI 문구:

```
촬영 품질
 ● 정밀 (120fps)   ← 기본
   공 궤적을 더 정확하게 추적합니다.
   배터리와 저장 공간을 더 사용합니다.

 ○ 표준 (60fps)
   배터리와 저장 공간을 아낍니다.
```

**정확도 차이를 반드시 표시합니다.** 사용자가 "배터리 아끼려고" 60fps를 고르면 궤적 검출률이 떨어지는데, 그 인과를 모르면 앱이 부정확하다고 판단하게 됩니다.

### ⚠️ 분석 결과에 촬영 fps를 기록한다

fps가 검출 품질을 좌우하므로 **`Clip` 엔티티에 `captureFPS`를 저장**합니다.

- 세션 간 비교 시 fps가 다르면 나란히 놓지 않는다
- 진척도 그래프에서 fps 변경 지점을 표시한다
- 골든 테스트 픽스처는 fps별로 분리한다
- Phase 0 게이트 측정도 fps별로 따로 집계한다 (5.5절)

### 해상도

**1080p (1920×1080)** 고정. 4K는 다음 이유로 채택하지 않습니다.

- 공이 커지는 이점(30 px)은 있으나 프레임당 처리량이 4배가 되어 [성능 예산](VISION-PIPELINE.md#37-성능-예산)을 초과합니다
- 저장 용량이 급증합니다
- 분석 입력은 어차피 640×360으로 다운스케일합니다

### 포맷 선택 구현

`AVCaptureSession.Preset`은 프레임레이트를 표현하지 못하므로 `activeFormat`을 직접 고릅니다.

```swift
// VisionKit/Camera/FormatSelector.swift
func selectFormat(_ device: AVCaptureDevice,
                  targetFPS: Double,
                  width: Int32 = 1920) -> AVCaptureDevice.Format? {
    device.formats.first { format in
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard dims.width == width else { return false }
        return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
    }
}

try device.lockForConfiguration()
device.activeFormat = format                       // 먼저 포맷
device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
device.unlockForConfiguration()
```

순서가 중요합니다. `activeFormat`을 바꾸면 프레임 듀레이션이 리셋되므로 **포맷 → 듀레이션** 순으로 설정합니다.

**제약**
- 고프레임 포맷은 `.builtInWideAngleCamera` 전용인 경우가 많습니다
- 비닝 포맷이라 실효 해상도가 낮을 수 있습니다 (`format.isVideoBinned` 확인)
- 비디오 안정화가 비활성화될 수 있으나, **고정 카메라라 안정화는 오히려 꺼야 하므로 문제없습니다**

## 5.3 노출 — 이것이 궤적 검출을 좌우한다

**셔터 속도가 프레임레이트보다 중요합니다.**

시속 100 km(27.8 m/s) 공은 노출 시간 동안 번집니다. 6 m 거리, 1080p 기준:

| 노출 | 이동 거리 | 화면 번짐 | 판정 |
|---|---|---|---|
| 1/60 s | 46 cm | 107 px | ❌ 공(15px)이 완전히 뭉개짐 |
| 1/120 s | 23 cm | 53 px | ❌ |
| 1/500 s | 5.6 cm | 13 px | ⚠️ 경계 |
| **1/1000 s** | **2.8 cm** | **6 px** | ✅ |

자동 노출에 맡기면 실패합니다. **노출을 짧게 고정해야 합니다.**

```swift
try device.lockForConfiguration()
device.setExposureModeCustom(
    duration: CMTime(value: 1, timescale: 1000),   // 1/1000s
    iso: AVCaptureDevice.currentISO                 // ISO는 자동 유지
)
device.unlockForConfiguration()
```

### 조명 조건

노출을 줄이면 어두워집니다. 따라서 조건별로 다릅니다.

| 조건 | 목표 노출 | 비고 |
|---|---|---|
| **실외 맑음** | 1/1000 s | **Phase 0 기준 조건** |
| 실외 흐림 | 1/500 s | ISO 상승, 노이즈 증가 |
| 실내 (밝은 조명) | 1/250 s | 검출률 하락 예상 |
| 실내 (어두움) | — | 지원 대상 아님 |

ISO 상한을 두고, 상한에 도달하면 노출을 단계적으로 늘리는 폴백을 둡니다. 이때 **사용자에게 "조명이 부족해 궤적 정확도가 떨어질 수 있음"을 알립니다.**

## 5.4 궤적 검출 파라미터 초기값

5.1절의 배치 스펙에서 유도한 시작값입니다. **Phase 0에서 실측으로 튜닝합니다.**

| 파라미터 | 초기값 | 근거 |
|---|---|---|
| `objectMinimumNormalizedRadius` | 0.002 | 8 m 거리의 공 (반지름 약 4 px / 1920) |
| `objectMaximumNormalizedRadius` | 0.015 | 5 m 거리 + 모션 블러로 늘어난 여유 |
| `trajectoryLength` | 5 | 최소값. Phase 0에서는 **검출 상한을 재기 위해 관대하게** 시작 |
| `frameAnalysisSpacing` | `.zero` | 전 프레임 분석 (궤적 스트림) |
| `targetFrameTime` | 1/fps | 프레임 듀레이션과 일치 |

**Phase 0 이후 조정 방향**: `trajectoryLength`를 8~10으로 올리면 오검출(사람 움직임, 다른 코트의 공)이 줄지만 검출률도 함께 떨어집니다. 5.5절의 오검출률 측정 결과를 보고 정합니다.

## 5.5 Phase 0 게이트 측정 방법

> 측정 정의가 없으면 게이트는 판정할 수 없습니다. "된 것 같은데?"로 끝납니다.

### 정의

| 항목 | 정의 |
|---|---|
| **분모** | 영상을 사람이 보며 센 **실제 타구 수** (라켓에 공이 맞은 횟수) |
| **분자** | 임팩트 프레임 ±3프레임 내에 시작하고 **0.2초 이상 이어진** 궤적이 검출된 타구 수 |
| **검출률** | 분자 / 분모 |
| **오검출** | 실제 타구와 무관하게 검출된 궤적 수 / 전체 검출 궤적 수 |

"궤적 하나라도 잡히면 성공"으로 하면 안 됩니다. 임팩트 시점과 무관한 짧은 궤적은 [비전 파이프라인 3.3절](VISION-PIPELINE.md#33-스윙-검출-및-분류)의 임팩트 프레임 교차 검증에 쓸 수 없습니다.

### 표본

**fps별로 따로 집계합니다** (5.2절).

| 조건 | 최소 타구 수 | 우선순위 |
|---|---|---|
| 실외 맑음 · 단순 배경 | 30 | **게이트 판정 기준** |
| 실외 맑음 · 복잡 배경 (펜스·관중) | 20 | 중요 |
| 실외 흐림 | 20 | 중요 |
| 실내 | 20 | 참고 |

**게이트는 "실외 맑음 · 단순 배경 · 120 fps" 조건에서 판정**합니다. 가장 유리한 조건에서도 70%를 못 넘으면 접근 방식 자체가 잘못된 것입니다.

### 기록 포맷

클립마다 JSON 한 개를 남기고 `ml/evaluation/phase0/`에 모읍니다.

```json
{
  "clipId": "2026-09-20-outdoor-sunny-01",
  "condition": { "location": "outdoor", "light": "sunny", "background": "simple" },
  "capture": { "fps": 120, "resolution": "1920x1080",
               "exposureDuration": "1/1000", "distanceM": 6.0, "heightM": 1.1 },
  "params": { "trajectoryLength": 5, "minRadius": 0.002, "maxRadius": 0.015 },
  "groundTruth": { "impactFrames": [142, 389, 601] },
  "detected":   [ { "startFrame": 143, "durationSec": 0.42, "matchedImpact": 142 },
                  { "startFrame": 390, "durationSec": 0.31, "matchedImpact": 389 },
                  { "startFrame": 512, "durationSec": 0.21, "matchedImpact": null } ],
  "result": { "hits": 2, "total": 3, "detectionRate": 0.667, "falsePositives": 1 }
}
```

`groundTruth.impactFrames`는 **수동 라벨링**합니다. 영상을 프레임 단위로 넘기며 임팩트 프레임을 기록하는 간단한 도구를 Phase 0에서 함께 만듭니다 (Mac 커맨드라인 또는 앱 내 디버그 화면).

### 판정

| 결과 | 조치 |
|---|---|
| 검출률 ≥ 70 % | ✅ 게이트 통과. Phase 1 진행 |
| 50 ~ 70 % | ⚠️ 파라미터·노출·거리 튜닝 후 재측정. 그래도 미달이면 아래로 |
| < 50 % | ❌ 접근 재설계. [D-20](../05-결정/stack/D-20-server-ml.md) 서버 TrackNet 도입 또는 궤적 기능을 v1 범위에서 제외 |

## 5.6 프레이밍 가이드 (앱 UI)

5.1절 스펙을 사용자가 맞출 수 있게 돕는 온보딩·촬영 화면 요소입니다. [R-2 카메라 흔들림](../04-계획/ROADMAP.md#상세-r-2-카메라-흔들림) 대응의 실체입니다.

| 요소 | 동작 |
|---|---|
| 거리 가이드 | 화면에 인체 실루엣 오버레이. 선수가 프레임 높이의 35~45%를 차지하도록 유도 |
| 수평 가이드 | 가속도계로 기울기 표시. ±3° 벗어나면 경고 |
| 흔들림 감지 | `CMMotionManager`로 진동 측정. 임계 초과 시 **궤적 기능 자동 비활성화 + 사유 표시** |
| 조명 경고 | ISO가 상한에 도달하면 "궤적 정확도가 떨어질 수 있음" 안내 |
| 각도 안내 | 온보딩에서 "코트 옆에서 선수를 옆모습으로" 일러스트 |

흔들림이 심하면 **조용히 실패하지 않고 이유를 보여주는 것**이 중요합니다. `DetectTrajectoriesRequest`는 고정 카메라가 전제이며, 이건 튜닝으로 해결되지 않습니다.

## 5.7 미결 사항

- ⬜ 화각 70° 가정의 실측 보정 (Phase 0 첫날)
- ⬜ 기기별 지원 포맷 덤프 및 최소 지원 기기 확정
- ⬜ 좌/우 핸드 대응 — 좌우 반전으로 충분한지, 카메라를 반대편에 두게 할지
- ⬜ 서브 촬영은 별도 배치가 필요한지 (임팩트가 2.7 m로 높음)

## 관련 문서

- [비전 파이프라인](VISION-PIPELINE.md)
- [스켈레톤 오버레이](SKELETON-OVERLAY.md)
- [제품 개요](../01-제품/PRODUCT-OVERVIEW.md)
- [로드맵과 리스크](../04-계획/ROADMAP.md)
- [D-04 비동기 / 스트림 분리](../05-결정/stack/D-04-concurrency.md)

---

[← 문서 허브](../INDEX.md)
