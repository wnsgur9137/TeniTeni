---
title: "SPEC-0040 RenderTransform 단일 변환 행렬"
aliases: ["SPEC-0040", "RenderTransform"]
tags:
  - 문서유형/기획
  - 영역/코어
issue: 40
type: "✨Feature"
area: "🧩Core"
created: 2026-09-14
updated: 2026-09-14
status: active
---

# SPEC-0040. RenderTransform 단일 변환 행렬

> 이슈 [#40](https://github.com/wnsgur9137/TeniTeni/issues/40) · 마일스톤 `0-D 파이프라인`

## 배경

Vision은 **정규화 좌표 + 좌하단 원점**, Metal NDC는 **-1~1 + 좌하단 원점**입니다. 여기에 aspect-fill 크롭, 디바이스 회전, 전면 카메라 미러링이 겹칩니다.

`AVCaptureVideoPreviewLayer`를 쓰지 않기로 확정했으므로([D-07](../05-결정/stack/D-07-overlay-rendering.md)) `layerPointConverted(fromCaptureDevicePoint:)`도 쓸 수 없습니다. 변환을 직접 만들되 **카메라 텍스처와 관절 좌표에 같은 행렬을 적용**합니다 — 두 곳이 같은 행렬을 쓰면 어긋날 수 없습니다.

설계는 [스켈레톤 오버레이 4.3](../02-설계/SKELETON-OVERLAY.md)에 있습니다. **행렬 규약은 거기서 확정됐으므로 재론하지 않습니다.**

### 왜 지금인가

[작업 순서 9.3](../04-계획/WORK-PLAN.md)의 0-D 표에서 **궤적에 의존하지 않는 다섯 작업 중, 실기기 없이 완결되는 유일한 항목**입니다. 순수 `simd_float4x4` 행렬 수학이라 카메라도 GPU도 필요 없습니다.

[#4](https://github.com/wnsgur9137/TeniTeni/issues/4)(실기기)와 0-B(촬영)가 사람의 일정에 달려 있어 게이트 판정 시점을 예측할 수 없는데, 이 작업은 그것을 기다리지 않습니다.

## 범위

### 만들 것

- `TeniVision/Sources/Render/RenderTransform.swift`
- aspect-fill 스케일 · y축 뒤집기 · 회전 · 미러링을 하나의 `simd_float4x4`로
- `ndc(visionPoint:)` — Vision 좌표(y-up) → NDC
- **`TeniVisionTests` 타깃 신설**
- 세로/가로 × 전면/후면 네 조합의 단위 테스트

### 만들지 않을 것

- **Metal 렌더 패스·셰이더** — 0-D #1·#5. 행렬을 uniform으로 넘기는 것은 #1 이후
- **`RotationCoordinator` 연동** — 실기기에서만 확인 가능. 행렬은 각도를 **인자로 받습니다**
- **`BallGeometry` 등 기존 TeniVision 테스트 이관** — `SynthTests`에 있는 것을 옮기는 것은 순수 이동이고 별개 작업입니다 (규약 12.8)
- **관절 좌표 → 정점 버퍼 변환** — 0-D #5

## 구현 선택지

### 1. 테스트를 어디에 두는가

TeniVision에는 **테스트 타깃이 없습니다.** 소스 6개가 전부 미검증입니다 — 단 `BallGeometry`만 `TeniToolTests/SynthTests.swift`에서 간접적으로 덮입니다(`TeniToolKit`이 TeniVision에 의존).

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. `TeniVisionTests` 타깃 신설** | 게이트가 `product: .unitTests`를 감지해 **자동으로 `test`를 돈다.** Render·Pose·Swing·Metrics가 앞으로 들어올 자리가 생긴다 | 타깃 하나 추가 |
| B. `TeniToolTests`에서 테스트 | 새 타깃 없음. `BallGeometry`의 기존 관례 | **CLI 도구 테스트가 렌더 코드를 떠안는다.** 오프라인 분석 도구는 화면 변환과 무관하다 |
| C. 앱 타깃 테스트 | — | iOS 시뮬레이터 필요. 게이트의 iOS 잡은 `build`만 돈다 |

**채택: A.** B가 기존 관례이긴 하나, TeniVision이 [9.6](../04-계획/WORK-PLAN.md)에서 **Pose / Ball / Render / Swing / Metrics**를 담기로 한 모듈입니다. 그 전부를 CLI 테스트 번들로 검증하는 것은 지금 한 파일일 때만 성립합니다.

`scripts/verify-ios.sh`가 `Projects/<스킴>/Project.swift`에서 `product: .unitTests`를 찾아 `build`를 `test`로 바꾸므로, **타깃만 추가하면 게이트가 자동으로 집습니다.**

### 2. ⚠️ 회전과 aspect-fill의 순서

[4.3](../02-설계/SKELETON-OVERLAY.md)의 예시 코드는 이렇습니다.

```swift
// 1. aspect-fill 스케일 — 회전 전 버퍼 크기로 계산
let bufferAspect = Float(bufferSize.width / bufferSize.height)
let viewAspect = Float(viewSize.width / viewSize.height)
...
// 3. 회전
m = r * m
```

**aspect-fill을 회전 전 버퍼 기준으로 계산하고, 회전을 나중에 곱합니다.**

실제 상황을 넣어보면 문제가 보입니다. 센서 버퍼는 가로(1920×1080), 뷰는 세로(390×844), `videoRotationAngle`은 90°입니다.

| | 값 |
|---|---|
| `bufferAspect` | 1920/1080 = **1.778** |
| `viewAspect` | 390/844 = **0.462** |
| 코드의 판정 | `bufferAspect > viewAspect` → `sx = 3.848` (좌우가 넘침) |
| 회전 후 실제 버퍼 | 1080×1920 → 종횡비 **0.563** |
| 올바른 판정 | 0.563 > 0.462 → 역시 좌우가 넘치지만 `sx = 1.218` |

**스케일이 3.16배 틀립니다.** 회전을 적용하면 비균등 스케일이 축과 함께 돌아가므로, 회전 전 종횡비로 계산한 값을 그대로 쓸 수 없습니다.

| 선택지 | 내용 |
|---|---|
| **A. 90°·270°면 버퍼 종횡비를 뒤집어 계산** | `bufferSize`를 회전 후 크기로 바꿔 스케일을 구한 뒤 회전을 곱한다 |
| B. 회전을 먼저 곱하고 스케일을 나중에 | 순서를 바꾸면 스케일이 뷰 축에 적용된다. 수식이 덜 직관적이다 |
| C. 그대로 두고 호출부가 회전된 크기를 넘긴다 | 계약이 암묵적이 된다. 호출부가 틀리면 조용히 어긋난다 |

**채택: A.** `RenderTransform` 안에서 `rotationAngle`을 보고 종횡비를 결정합니다. 호출부는 **센서가 준 버퍼 크기를 그대로** 넘깁니다.

> **이것은 설계 문서의 예시 코드를 고치는 것입니다.** 4.3은 "확정"으로 표시돼 있으나 그 확정 대상은 **단일 행렬을 텍스처와 관절에 함께 쓴다는 구조**이지, 예시 코드의 산술이 아닙니다. 구조는 그대로 두고 산술만 고칩니다. 구현 후 4.3을 갱신합니다.

### 3. 회전각의 단위

`AVCaptureDevice.RotationCoordinator.videoRotationAngle`이 **도(degree)** 를 냅니다. 4.3의 코드도 도를 받아 내부에서 라디안으로 바꿉니다.

**채택: 도 그대로.** 호출부가 변환하면 그 변환이 두 곳에 생깁니다.

## 완료 기준

- [ ] `RenderTransform(bufferSize:viewSize:rotationAngle:isMirrored:)`가 `simd_float4x4`를 만든다
- [ ] `ndc(visionPoint:)`가 Vision 좌표(y-up)를 NDC로 옮긴다
- [ ] `TeniVisionTests` 타깃이 생기고 **게이트가 `build`가 아니라 `test`를 돈다**
- [ ] **종횡비가 같으면 스케일이 1** — 1920×1080 버퍼 / 1920×1080 뷰에서 `sx == sy == 1`
- [ ] **모서리 왕복** — 스케일 1일 때 이미지 (0,0)→NDC (-1,+1), (1,1)→(+1,-1)
- [ ] **중심 불변** — 모든 조합에서 이미지 (0.5,0.5)가 NDC (0,0)
- [ ] **aspect-fill 방향** — 버퍼가 뷰보다 넓으면 x가 넘치고 y는 1, 좁으면 반대
- [ ] **90° 회전에서 스케일이 회전 후 종횡비로 계산된다** (선택지 2)
- [ ] **미러링** — 전면에서 x 부호가 뒤집히고, 후면에서 그대로
- [ ] **Vision y 뒤집기** — visionPoint (0,0)이 화면 **아래쪽**으로 간다
- [ ] `scripts/verify-ios.sh` 통과, 경고 0

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `scripts/verify-ios.sh` (`CLEAN_BUILD=1`로 한 번 더) |
| 행렬 정확성 | 손으로 계산한 NDC를 단위 테스트로 고정. 부동소수 비교는 허용오차를 명시 |
| 네 조합 | 세로/가로 × 전면/후면을 각각 케이스로 |
| 회전 순서 | 90°에서 스케일이 3.848이 아니라 1.218인지 |
| 변이 시험 | y 뒤집기를 빼고, 미러링 부호를 뒤집어 **테스트가 잡는지 확인** |
| 테스트 실행 확인 | 로그에 `TeniVisionTests` 스위트 이름이 찍히는지 |

**마지막 둘이 중요합니다.** 이 작업은 산출물이 순수 함수라 "통과했다"가 쉽고, 그래서 **틀린 것을 통과시키기도 쉽습니다.** 변이를 넣어 테스트가 실제로 잡는지 확인합니다.

## 영향받는 문서

- [스켈레톤 오버레이 4.3](../02-설계/SKELETON-OVERLAY.md) — 예시 코드의 aspect-fill 산술 정정 (선택지 2)
- [스켈레톤 오버레이 4.10](../02-설계/SKELETON-OVERLAY.md) — `RenderTransform` 체크박스
- [작업 순서 9.3](../04-계획/WORK-PLAN.md) — 0-D 2번

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| **회전 순서 문제가 선택지 2로 안 끝난다** | 실기기에서 스켈레톤이 어긋난다 | 네 조합을 전부 테스트로 고정. 그래도 실기기에서 어긋나면 0-D #5에서 드러난다 — **그때 고칠 수 있게 행렬을 한 곳에 모아둔다** |
| 손계산 기댓값 자체가 틀림 | 틀린 것을 고정한다 | 대칭성으로 교차 검증 — 중심은 항상 (0,0), 미러링은 x 부호만 뒤집음, 90°×4 = 항등 |
| 부동소수 비교 실패 | 테스트가 간헐적으로 깨짐 | 허용오차를 상수로 두고 명시. `==` 쓰지 않음 |
| `TeniVisionTests` 추가로 게이트가 느려짐 | 반복 저하 | 순수 계산이라 밀리초 단위. `TeniTool`의 184초와 비교 불가 |

## 미수행으로 남길 것

- **실기기에서 스켈레톤이 몸과 맞는가** — 0-D #5 이후, 실기기 필요
- **`RotationCoordinator`가 실제로 내는 각도** — 실기기 필요. 이 작업은 각도를 **받기만** 합니다
- **셰이더에서의 행렬 적용** — 0-D #1 이후
- **기존 TeniVision 소스 5개의 테스트** — 이 작업은 `Render`만 덮습니다. 나머지는 별도

## 관련 문서

- [스켈레톤 오버레이 4.3·4.10](../02-설계/SKELETON-OVERLAY.md) — 설계 정본
- [D-07 오버레이 렌더링](../05-결정/stack/D-07-overlay-rendering.md)
- [작업 순서 9.3](../04-계획/WORK-PLAN.md) — 0-D 표

---

[← 문서 허브](../INDEX.md)
