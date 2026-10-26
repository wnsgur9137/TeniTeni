---
title: "SPEC-0096 카메라 프레임을 포즈로 바꾼다"
aliases: ["SPEC-0096", "카메라 프레임을 포즈로 바꾼다"]
tags:
  - 문서유형/기획
  - 영역/코어
issue: 96
type: feature
area: core
created: 2026-10-23
updated: 2026-10-23
status: active
---

# SPEC-0096. 카메라 프레임을 포즈로 바꾼다

> 이슈 [#96](https://github.com/wnsgur9137/TeniTeni/issues/96)

## 배경

1-B의 부품은 전부 만들어졌고 전부 단위 테스트를 통과한다 — [SPEC-0085](SPEC-0085-swing-trigger.md)의 `SwingTrigger`, [SPEC-0091](SPEC-0091-swing-clip-recording.md)의 `ClipRecorder`·`SessionBuilder`. 그런데 **어느 것도 실행되지 않는다.** 입력이 없기 때문이다.

촬영 화면이 쓰는 `CameraController`는 Phase 0-A의 최소 구현이다. `AVCaptureMovieFileOutput`으로 통영상 하나를 찍을 뿐, 프레임을 한 장씩 꺼내는 경로가 없다. `PoseFrame`은 주석에 "Vision 관측 → `PoseFrame` 어댑터는 포즈 검출이 만든다"고 적어 둔 채 비어 있다.

이 작업은 그 빈 칸을 채운다. **카메라 → 프레임 → 포즈** 까지만 간다. 포즈에서 스윙·클립까지 잇는 것은 [#97](https://github.com/wnsgur9137/TeniTeni/issues/97)이다.

스택은 이미 정해져 있다 — [D-01](../05-결정/stack/D-01-deployment-target.md) iOS 26, [D-04](../05-결정/stack/D-04-concurrency.md) 스트림 분리, [D-06](../05-결정/stack/D-06-pose-engine.md) Vision 신규 Swift API. 배치도 [동시성 6.2~6.4](../02-설계/CONCURRENCY.md)가 표와 코드 스케치까지 갖고 있다. 여기서는 **그 설계가 실제 타입과 만나는 지점에서 갈리는 것만** 다룬다.

## 범위

### 만들 것

**`Presentation`(iOS 전용)**

- `FrameIntake` — `AVCaptureVideoDataOutput` 델리게이트. `nonisolated`, 전용 `DispatchQueue`, `alwaysDiscardsLateVideoFrames = true`. 콜백은 감싸서 넘기기만 하고 즉시 반환한다
- `ReadyFrame` — `CMReadySampleBuffer<CVReadOnlyPixelBuffer>` 래퍼. `TeniVision.ClipFrame`을 준수해 #97에서 `ClipRecorder`에 그대로 들어간다
- `FrameDownscaler` — 분석 입력을 640×360으로 줄인다. `VTPixelTransferSession` + `CVPixelBufferPool`
- `PoseStream` — `AsyncStream(bufferingNewest(1))`을 **단일 `Task`** 가 소비한다. actor가 아니다(동시성 6.1). 120fps면 2프레임에 1장으로 데시메이션
- `CameraController`에 비디오 데이터 출력을 추가한다. 기존 `AVCaptureMovieFileOutput` 경로는 **건드리지 않는다**

**`TeniVision`(iOS + macOS)**

- `Pose/BodyPoseObservable` — 어댑터가 읽는 경계 프로토콜. `HumanBodyPoseObservation`이 확장으로 준수한다
- `Pose/PoseFrameAdapter` — 관측 → `PoseFrame`. 관절 6개만, 정규화 좌표(좌하단 원점) 그대로
- `Pose/PoseEstimator` — `DetectHumanBodyPoseRequest` 래핑. 여러 사람이 잡히면 하나를 고른다

**화면**

- 촬영 화면에 "사람이 잡히는가"를 표시한다. 6m 밖에서 읽혀야 한다([SPEC-0022](SPEC-0022-capture-6m-readability.md))

### 만들지 않을 것

- **스켈레톤 렌더링.** Metal 파이프라인은 0-D의 일이다([스켈레톤 오버레이 4.1](../02-설계/SKELETON-OVERLAY.md))
- **One Euro Filter 스무딩.** 트리거는 각속도를 쓰므로 떨림에 민감하지만, 필터를 넣으면 지연이 생긴다. 실기기에서 떨림을 **보고 나서** 넣는다
- **`detectsHands`.** 그립 분석은 v1 범위 밖이고, 켜면 프레임당 비용이 는다
- 3D 포즈, 궤적 검출, 다중 인물 추적
- `SwingTrigger`·`ClipRecorder` 배선 — [#97](https://github.com/wnsgur9137/TeniTeni/issues/97)

## 구현 선택지

### 1. Vision에 무엇을 넘기는가

`DetectHumanBodyPoseRequest.perform(on:orientation:)`은 `CVPixelBuffer`나 `CMSampleBuffer`를 받는다. `CMReadySampleBuffer`는 받지 않는다. 그런데 `CVReadOnlyPixelBuffer`가 내주는 `CVPixelBuffer`는 `withUnsafeBuffer(_:)`의 **동기 클로저 안에서만** 유효하고, `perform`은 `async`다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| 원본 버퍼를 클로저 밖으로 꺼내 넘긴다 | 복사 0 | `withUnsafeBuffer`가 거는 수명 보장이 타입에서 사라진다. 1080p 입력이라 포즈 비용도 예산을 넘는다 |
| **다운스케일한 사본에 돌린다** | 소유권이 분명하다 — 사본은 우리 것이다. 640×360이면 포즈 3~5ms로 [성능 예산 3.7](../02-설계/VISION-PIPELINE.md)에 들어간다 | 전송 1회(하드웨어 가속). 풀 관리 코드가 는다 |
| 델리게이트 큐에서 바로 Vision을 호출한다 | 중간 타입이 없다 | 콜백을 붙들어 캡처 풀이 고갈된다 — [동시성 6.1](../02-설계/CONCURRENCY.md) 위반 |

**채택**: 다운스케일한 사본. 설계가 "분석 입력은 반드시 다운스케일한다"를 이미 정했고, 수명 문제가 거기서 함께 풀린다.

> **구현에서 드러난 것 — `sending` 간극.** `CMReadySampleBuffer.init(unsafeWithPixelBuffer:)`는 `sending CMSampleBuffer`를 요구하는데, AVFoundation의 델리게이트 인자는 `sending`으로 선언돼 있지 않다(SDK 헤더 확인). `CMSampleBufferCreateCopy`로 사본을 만들어도 "입력에서 파생됐다"는 사실이 남아 영역 검사를 통과하지 못한다. 그래서 **사본을 만들고 그 한 줄에서만 `nonisolated(unsafe)`로 검사를 끊었다.** `@unchecked Sendable`을 쓰지 않으면서 경계를 넘는 유일한 길이었다.
>
> 끊어도 되는 근거는 **"사본이 우리 것이니 원본은 풀로 돌아간다"가 아니다.** 그 복사는 얕고 `CVImageBuffer`를 공유한다. 실제 근거는 전달 뒤 AVFoundation도 이 함수도 그 픽셀을 다시 쓰지 않는다는 것이고, 대신 **`ReadyFrame` 한 장이 캡처 풀 버퍼 한 장을 점유한다.** 공짜가 아니다 — 전 프레임을 링 버퍼에 담는 [#97](https://github.com/wnsgur9137/TeniTeni/issues/97)은 상한을 명시적으로 걸어야 한다.
>
> 또 `init(unsafeWithPixelBuffer:)`는 **실패 가능 생성자가 아니고 내용을 검사하지도 않는다.** 샘플에 이미지 버퍼가 없으면 잘못된 프레임이 만들어져 분석 Task 깊은 곳에서 터진다. 동적 내용으로 감싼 뒤(`init(unsafeBuffer:)`) 실패 가능 다운캐스트(`init?(_:)`)로 걸러낸다.
>
> 또 `PoseEstimator.frame(in:)`의 버퍼 인자를 `sending`으로 받지 않는다. 받으면 호출부가 루프에서 그 버퍼를 들고 있는 것조차 "전달 후 사용"이 되어 컴파일되지 않는다. 양쪽이 모두 `nonisolated`이므로 넘길 경계가 없다.

### 2. 어댑터를 무엇으로 테스트하는가

`HumanBodyPoseObservation`에는 합성할 생성자가 없다. 있는 것은 `init(_ observation: VNHumanBodyPoseObservation)` 뿐이고, 그 레거시 타입도 합성할 수 없다. 관측을 입력으로 삼으면 **실기기 없이는 어댑터를 한 줄도 검증할 수 없다.**

| 선택지 | 장점 | 단점 |
|---|---|---|
| 관측을 직접 받는다 | 중간 타입 0 | 테스트 불가. 실기기에서만 확인된다 |
| `Decodable`로 JSON 픽스처를 만든다 | 실제 타입 그대로 | 인코딩 포맷이 문서화돼 있지 않다. OS 업데이트로 말없이 깨진다 |
| **자체 경계 프로토콜을 둔다** | 가짜 구현으로 전수 검증. 관절 6개만 노출하므로 경계가 좁다 | 프로토콜 하나가 는다. 확장 준수부는 테스트가 못 덮는다(한 줄짜리 전달) |

**채택**: 경계 프로토콜. `PoseFrame`이 "Vision 타입을 직접 받지 않는다"고 적어 둔 이유와 같은 이유다.

### 3. 여러 사람이 잡히면

코트에는 상대도 있고 뒤 코트 사람도 있다. 요청은 관측 배열을 돌려준다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| 첫 번째를 쓴다 | 가장 단순 | 순서가 보장되지 않는다. 프레임마다 다른 사람을 볼 수 있다 |
| **어깨 폭이 가장 큰 사람** | 카메라에 가까운 사람 = 촬영 대상. 트리거가 이미 어깨 폭을 기준 길이로 쓴다 | 대상이 옆을 보면 어깨 폭이 줄어 뒷사람에게 뺏길 수 있다 |
| 프레임 간 추적으로 동일인을 유지한다 | 가장 정확 | 추적기가 필요하다. 이번 범위를 넘는다 |

**채택**: 어깨 폭 최대. 뺏김은 실기기에서 보고 나서 추적을 붙인다.

## 완료 기준

- [x] `PoseFrameAdapter`가 가짜 관측으로 검증된다 — 관절 6개 매핑, 좌표 원점 보존, 관절 결손, **신뢰도는 그대로 전달**
      — 기획 단계에서 "신뢰도 임계 미만 제외"로 적었던 것은 틀렸다. 어댑터가 걸러내면 같은 판단이 `PoseFrame.point(_:minimumConfidence:)`와 두 곳에 생기고, 둘이 어긋나면 트리거가 조용히 신호를 잃는다. 임계는 프로파일의 일이다.
- [x] `PoseEstimator`의 **사람 선택 규칙**이 가짜 관측 여러 개로 검증된다
- [x] `FrameDownscaler`가 합성 `CVPixelBuffer`로 검증된다 — 출력 크기, **전송된 픽셀 값**, 풀을 세운 횟수(재사용), 입력 크기가 바뀌어도 깨지지 않는다
- [x] 데시메이션이 검증된다 — `FrameIntake.intake(_:)`를 카메라 없이 불러 **실제 호출 횟수**를 센다. 간격 산술은 따로 보되 119.88fps(NTSC)와 목표 배수 근처 값까지 포함한다
- [x] `ReadyFrame`이 `ClipFrame`을 준수한다(컴파일로 보장) — #97이 그대로 쓴다
- [x] 클린 빌드(`CLEAN_BUILD=1`) 경고 **0**
- [x] 촬영 화면이 포즈 상태를 표시한다 — "사람이 보입니다 / 안 보입니다 / **자세가 잘 안 보입니다**". 셋째 상태를 둔 이유는 측면으로 선 사용자가 프레임 안에 멀쩡히 있는데도 자리를 옮기기 때문이다
- [x] 표시 판정이 **프레임 시계**로 이뤄진다 — 벽시계로 재면 메인이 수백 ms 막혔다 풀릴 때 멀쩡한 상태에서 "끊겼다"가 뜬다
- [x] 드롭된 프레임을 센다 — 포즈가 예산을 넘겼는지 실기기에서 읽을 유일한 단서다

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `DEVELOPER_DIR=… CLEAN_BUILD=1 ./scripts/verify-ios.sh` |
| 문서 게이트 | `./scripts/verify-docs.sh` |
| 어댑터·선택 규칙 | `TeniVisionTests` — 가짜 `BodyPoseObservable` |
| 다운스케일 | `PresentationTests` — `CVPixelBufferCreate`로 만든 합성 버퍼 |
| 데시메이션 | `PresentationTests` — 가짜 프레임 시퀀스, 호출 횟수 계수 |
| 테스트가 의미 있는가 | 뮤테이션 — 임계 비교 뒤집기, 선택 규칙을 `first`로 바꾸기, 데시메이션 상수 바꾸기 |

## 영향받는 문서

- [CONCURRENCY.md](../02-설계/CONCURRENCY.md) 6.2 — `PoseAnalyzer` 행을 "구현됨"으로. 6.3 인테이크 스케치를 실제 코드와 맞춘다
- [SKELETON-OVERLAY.md](../02-설계/SKELETON-OVERLAY.md) 4.9 — `Pose/` 파일 배치를 실제와 맞춘다(이번에 만들지 않은 파일은 그대로 둔다)
- [VISION-PIPELINE.md](../02-설계/VISION-PIPELINE.md) 3.2 — 다중 인물 선택 규칙을 적는다(설계에 없다)
- [INDEX.md](../INDEX.md) — 이 문서 등재

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 시뮬레이터에 카메라가 없다 | 인테이크 경로가 **실행된 적 없는 코드**로 남는다 | 인테이크를 얇게 유지하고, 판단이 있는 부분(어댑터·선택·데시메이션·다운스케일)을 전부 카메라 밖으로 뺀다 |
| 포즈가 프레임 예산을 넘는다 | 프레임 드롭, 트리거가 신호를 잃는다 | 다운스케일 + 60fps 데시메이션. 실측은 실기기에서 |
| `CMReadySampleBuffer`가 기대대로 감싸지지 않는다 | 인테이크 설계가 흔들린다 | 구현 초기에 컴파일로 먼저 확인하고, 안 되면 기획서를 고친 뒤 진행 |
| 다운스케일이 종횡비를 바꾼다 | 관절 좌표가 왜곡돼 각도가 틀어진다 | 종횡비를 유지한다. 1920×1080 → 640×360은 정확히 같은 비율 |

## 미수행으로 남길 것

- **Vision 포즈 요청 자체가 시뮬레이터에서 돌지 않는다.** `No available compute device for VNComputeStageMain`으로 실패한다 — 구현 중 확인했다. 그래서 어댑터·선택·데시메이션·다운스케일은 전부 검증했지만 **요청과 그 결과를 쓰는 구간은 테스트가 덮지 못한다.** 테스트가 확인하는 것은 "프레임 한 장이 결과 하나로 끝나고 실패를 삼키지 않는다"까지다
- **실기기에서 사람이 실제로 잡히는가** — 카메라가 필요하다
- **회전각 → `CGImagePropertyOrientation` 매핑** — 실기기에서만 맞는지 확인된다. 다만 틀려도 기하는 무너지지 않는다: 트리거가 쓰는 각속도 크기와 몸통선 교차의 **부호 변화**는 화면 전체의 회전·거울에 불변이다. 영향은 "누워 있는 사람을 Vision이 못 찾는" 쪽이다
- **프레임 예산 실측** — A17 기준 3~5ms는 설계의 추정값이다
- **떨림 정도** — One Euro Filter가 필요한지는 보고 나서 정한다
- **6m 거리에서 포즈가 잡히는가** — 정규화 좌표에서 사람이 작아진다. 거리 한계는 실측 항목이다

## 관련 문서

- [SPEC-0085 스윙 트리거 룰 엔진](SPEC-0085-swing-trigger.md)
- [SPEC-0091 스윙 구간 클립 저장](SPEC-0091-swing-clip-recording.md)
- [02. 동시성 설계](../02-설계/CONCURRENCY.md)
- [03. 비전 파이프라인](../02-설계/VISION-PIPELINE.md)
- [04. 스켈레톤 오버레이](../02-설계/SKELETON-OVERLAY.md)

---

[← 문서 허브](../INDEX.md)
