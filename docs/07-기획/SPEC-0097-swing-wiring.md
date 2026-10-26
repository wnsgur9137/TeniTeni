---
title: "SPEC-0097 스윙 검출을 촬영에 배선한다"
aliases: ["SPEC-0097", "스윙 검출을 촬영에 배선한다"]
tags:
  - 문서유형/기획
  - 영역/코어
issue: 97
type: feature
area: core
created: 2026-10-26
updated: 2026-10-26
status: active
---

# SPEC-0097. 스윙 검출을 촬영에 배선한다

> 이슈 [#97](https://github.com/wnsgur9137/TeniTeni/issues/97)

## 배경

[#96](https://github.com/wnsgur9137/TeniTeni/issues/96)이 카메라에서 포즈까지를 이었다. 그 포즈를 받는 쪽이 아직 없다 — `SwingTrigger`([SPEC-0085](SPEC-0085-swing-trigger.md))도 `ClipRecorder`·`SessionBuilder`([SPEC-0091](SPEC-0091-swing-clip-recording.md))도 **여전히 아무도 부르지 않는다.** 촬영을 해도 스윙 클립이 한 장도 남지 않는다.

확인하면서 하나 더 드러났다. **`SwiftDataSessionRepository`는 만들어져 있지만 앱 어디에서도 생성되지 않는다.** 저장 경로의 끝이 비어 있으므로 이 작업이 그 배선까지 포함한다.

## 범위

### 만들 것

- `SwingPipeline`(`Presentation`) — 포즈 한 장을 받아 `SwingTrigger` → `ClipRecorder` → `SessionBuilder`까지 흘린다
- `PoseAnalyzer.run`의 결과 처리를 **`async` 클로저**로 바꾼다. 그래야 `actor ClipRecorder`를 **같은 단일 Task 안에서 순서대로** `await`할 수 있다
- `Domain.Handedness` → `TeniVision.RacketSide` 변환. `CaptureFeature.State`가 주 사용 손을 들고, `AppFeature`가 넘긴다
- 세션 수명: **녹화 버튼이 세션의 시작과 끝**이다. 시작에서 `SessionBuilder`를 열고, 정지에서 `finish(at:)`으로 저장한다
- `SwiftDataSessionRepository`를 진입점에서 만들어 `AppView` → `CaptureScreen` → `CameraController`로 명시 주입한다
- 촬영 화면에 **스윙 카운트**를 표시한다(목업의 원래 자리, 6m 가독성)

### 만들지 않을 것

- **전 프레임을 클립에 쓰지 않는다.** 아래 선택지 2 참조
- 보관함 화면에서 세션·클립을 보여주는 것 — 별도 작업이다
- 스윙 유형 분류, 메트릭 산출(1-D)
- 스켈레톤 오버레이(0-D), One Euro Filter

## 구현 선택지

### 1. 트리거를 어디에서 돌리는가

트리거는 **순서가 절대적인 상태 기계**다. `ClipRecorder`는 `actor`라 `await`가 필요하다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| 콜백에서 `Task { await ... }` | 변경 최소 | **순서가 깨진다.** 비구조 `Task`는 생성 순서대로 실행되지 않는다 — #96 리뷰가 같은 문제를 표시 판정에서 이미 잡았다 |
| `SwingPipeline`을 actor로 | 상태 보호가 명확 | `await` 지점에서 재진입돼 순서 보장이 코드에서 사라진다([동시성 6.1](../02-설계/CONCURRENCY.md)) |
| **결과 처리를 `async` 클로저로** | `for await` 루프가 한 장씩 끝까지 처리한다 — 순서가 **구조로** 보장되고 actor도 `await`할 수 있다 | `PoseAnalyzer.run`의 서명이 바뀐다 |

**채택**: `async` 클로저. 단일 Task 원칙을 지키면서 actor를 부를 수 있는 유일한 모양이다.

### 2. 클립에 어떤 프레임을 쓰는가

| 선택지 | 장점 | 단점 |
|---|---|---|
| 캡처 전 프레임(120fps) | 슬로모션 품질이 촬영 그대로 | `ReadyFrame` 한 장이 **캡처 풀 버퍼 한 장을 점유**한다(#96 리뷰 W4). 링 버퍼 상한 설계가 추가로 필요하고, 넘치면 프레임이 통째로 드롭된다 |
| **분석 프레임(데시메이션 후, 60fps)** | 점유가 이미 1장으로 묶여 있다. 트리거와 **같은 프레임 집합**이라 구간과 영상이 어긋날 수 없다 | 120fps로 찍어도 클립은 60fps다 |

**채택**: 분석 프레임. 120fps의 이점을 클립에서 잃는 것은 **의도된 트레이드오프**이고, 전 프레임 경로는 링 버퍼 상한을 설계한 뒤 별도 이슈로 올린다.

> ⚠️ **이 선택지의 전제가 틀렸다 — 구현 리뷰에서 드러났다.** "점유가 이미 1장으로 묶여 있다"는 포즈 스트림(`bufferingNewest(1)`)의 점유이고, 그 프레임을 `ClipRecorder`에 넘기는 순간 상한이 사라진다. `ClipRecorder`의 링 버퍼는 `preRoll + margin = 3.0초`를 들고 있으므로 **분석 60fps에서 상시 약 180장**이고, `ReadyFrame` 한 장은 캡처 풀 버퍼 한 장을 붙든다. 실기기에서는 수십 프레임 안에 출력 풀이 고갈되고 분석이 끊겨 **스윙이 하나도 잡히지 않는다** — 화면 증상은 "스윙 0"이고 원인은 드러나지 않는다.
>
> 시뮬레이터에서는 Vision이 실패해 `enqueue`에 도달조차 하지 않으므로 **재현되지 않는다.** 소급분을 캡처 풀 밖으로 옮기는 설계가 필요하고, 그것은 이 작업의 범위를 넘는다 — 후속 이슈로 분리했다.

### 3. 저장소를 어떻게 내려보내는가

`SessionRepository`는 `actor`이고 `CaptureFeature.State`는 `Equatable`이라 상태에 담을 수 없다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| TCA `@Dependency` | TCA 관례 | 프레임 경로는 **TCA 바깥**이다([D-03](../05-결정/stack/D-03-architecture-pattern.md)). 의존성 그래프가 두 갈래가 된다 |
| **진입점에서 명시 주입** | 소유자가 하나다. 생성 실패를 진입점이 한 번에 다룬다 | `AppView`·`CaptureScreen`의 서명이 길어진다 |

**채택**: 명시 주입. 저장소 생성이 실패하면 **촬영은 되지만 세션이 저장되지 않는다는 사실을 화면에 남긴다** — 조용히 버리지 않는다.

### 4. 프레임 시계의 원점

`RecordedClip.startedAt`은 부팅 이후 호스트 시각이다. `SessionBuilder`가 원점을 받아 뺀다([SPEC-0091](SPEC-0091-swing-clip-recording.md) 리뷰 CRITICAL).

**채택**: 녹화 시작 후 **첫 분석 프레임의 PTS**를 원점으로 잡고 그 시점에 `SessionBuilder`를 만든다. 프레임이 오기 전에는 원점을 알 수 없으므로 지연 생성이다.

## 완료 기준

- [ ] 가짜 포즈 스트림으로 **클립이 실제로 생기는지** 검증한다 — 카메라 없이
- [ ] 스윙 2개가 겹치면 클립 1개로 병합되는 경로가 배선에서도 성립한다
- [ ] 녹화를 멈추면 `postRoll`을 못 채운 마지막 스윙도 저장된다
- [ ] 세션이 저장되고, 저장된 `Clip.recordedAt`이 **세션 시작 기준 상대 시각**이다(부팅 시각이 새지 않는다)
- [ ] 스윙 0개로 끝난 세션도 저장된다
- [ ] 주 사용 손이 `RacketSide`로 옳게 변환된다
- [ ] 저장소 생성 실패 시 화면에 사유가 남는다
- [ ] 클린 빌드 경고 **0**
- [ ] 촬영 화면이 스윙 카운트를 6m에서 읽히는 크기로 표시한다

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `DEVELOPER_DIR=… CLEAN_BUILD=1 ./scripts/verify-ios.sh` |
| 문서 게이트 | `./scripts/verify-docs.sh` |
| 배선 전체 | `PresentationTests` — 가짜 추정기가 내놓는 포즈 시계열을 `SwingPipeline`에 먹여 **파일과 저장된 세션**을 확인한다 |
| 저장 | 가짜 `SessionRepository`로 호출 인자를 본다 |
| 테스트가 의미 있는가 | 뮤테이션 — 원점 빼기 제거, 손 변환 뒤집기, `finish` 생략, 겹침 병합 해제 |

## 영향받는 문서

- [ARCHITECTURE.md](../02-설계/ARCHITECTURE.md) 2.3 — 배선이 끝난 경로를 반영
- [CONCURRENCY.md](../02-설계/CONCURRENCY.md) 6.2 — `SwingPipeline` 행 추가
- [INDEX.md](../INDEX.md) — 이 문서 등재

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| `append`가 actor를 막아 프레임이 밀린다 | 드롭 → 트리거가 신호를 잃는다 | #96이 넣은 드롭 카운터로 실기기에서 읽는다 |
| 저장 중 앱이 종료된다 | 세션이 사라진다 | 클립 파일은 이미 디스크에 있다. 복구는 별도 작업 |
| 120fps 클립을 기대한다 | 리플레이 품질이 예상과 다르다 | 선택지 2에 명시. 전 프레임 경로는 후속 이슈 |

## 미수행으로 남길 것

- **캡처 풀 고갈 위험이 남아 있다**(위 선택지 2의 경고). 링 버퍼가 캡처 버퍼를 붙드는 구조를 고치지 않았다 — 실기기 측정 없이 상한을 정할 수 없고, 소급분을 어디로 옮길지는 클립 해상도와 맞바꾸는 **제품 결정**이다

- **실기기에서 실제 스윙이 검출되는가** — Vision이 시뮬레이터에서 돌지 않는다(#96에서 확인)
- 검출률·오검출률 — 코치 자문([#54](https://github.com/wnsgur9137/TeniTeni/issues/54))과 파라미터 스윕이 필요하다
- 클립 파일 용량·쓰기 지연 실측

## 관련 문서

- [SPEC-0096 카메라 프레임을 포즈로](SPEC-0096-pose-intake.md)
- [SPEC-0091 스윙 구간 클립 저장](SPEC-0091-swing-clip-recording.md)
- [SPEC-0085 스윙 트리거 룰 엔진](SPEC-0085-swing-trigger.md)
- [02. 동시성 설계](../02-설계/CONCURRENCY.md)

---

[← 문서 허브](../INDEX.md)
