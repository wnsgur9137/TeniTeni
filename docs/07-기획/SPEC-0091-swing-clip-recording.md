---
title: "SPEC-0091 스윙 구간 클립 저장"
aliases: ["SPEC-0091", "스윙 구간 클립 저장"]
tags:
  - 문서유형/기획
  - 영역/코어
issue: 91
type: feature
area: core
created: 2026-10-22
updated: 2026-10-22
status: draft
---

# SPEC-0091. 스윙 구간 클립 저장

> 이슈 [#91](https://github.com/wnsgur9137/TeniTeni/issues/91)

## 배경

[#85](https://github.com/wnsgur9137/TeniTeni/issues/85)가 `SwingCandidate`를 만들었지만 **그것을 받는 코드가 없습니다.** [#70](https://github.com/wnsgur9137/TeniTeni/issues/70)이 `Session`·`Clip`·`Swing`과 `SessionRepository`를 만들었지만 **채우는 코드가 없습니다.** 둘을 잇는 것이 1-B의 마지막 고리입니다.

[SPEC-0070](SPEC-0070-persistence-foundation.md)이 "클립 파일 저장 — `AVAssetWriter`는 촬영이 돌아야 합니다"라며 미뤘던 항목입니다.

구조는 이미 정해져 있습니다. 여기서 재론하지 않습니다.

| 이미 정한 것 | 어디 |
|---|---|
| 링 버퍼에서 `[t-2s, t+2s]`를 `AVAssetWriter`로 기록 | [아키텍처 2.3](../02-설계/ARCHITECTURE.md#23-데이터-흐름) |
| `ClipRecorder`는 `actor` — 링 버퍼와 `AVAssetWriter` 상태를 보호한다 | [동시성 6.2](../02-설계/CONCURRENCY.md#62-격리-도메인-배치) |
| 프레임은 경계에서 `CMReadySampleBuffer`로 감싼다 | [동시성 6.3](../02-설계/CONCURRENCY.md#63-프레임-소유권) |
| 메타데이터는 로컬 DB, 영상은 로컬 파일 | [아키텍처 2.4](../02-설계/ARCHITECTURE.md#24-도메인-모델) · [D-08](../05-결정/stack/D-08-local-db.md) |
| `preRoll` 2.0s · `postRoll` 2.0s · 재발화 간격 0.8s | [SPEC-0085](SPEC-0085-swing-trigger.md) |

## 범위

### 만들 것

- **`ClipPlan`** — 겹치는 후보를 한 구간으로 병합하고, `postRoll`이 지났는지 판정하는 상태 기계. 순수 계산
- **`actor ClipRecorder`** — 프레임을 링 버퍼에 담고, 플러시 시점에 구간을 꺼내 쓰기에 넘긴다
- **`ClipWriter`** — 픽셀 버퍼 시퀀스를 `.mov`로 쓴다
- **`TimedRingBuffer.entries(from:to:)`** — 타임스탬프를 함께 꺼낸다. 현재 `range(from:to:)`는 값만 주는데, 기록에는 각 프레임의 시각이 필요하다
- **세션 기록** — 쓴 결과를 `Session`·`Clip`·`Swing`으로 만들어 `SessionRepository`에 저장한다

### 만들지 않을 것

- **카메라 → 분석 배선** — 현재 `CameraController`는 `AVCaptureMovieFileOutput`으로 **세션 전체를 한 파일**에 씁니다. 프레임 단위 출력(`AVCaptureVideoDataOutput`)과 포즈 검출이 선행이고, 그것은 실기기가 필요합니다
- **오디오** — 스윙 클립에 소리를 넣지 않습니다. 분석에 쓰지 않고 프라이버시 범위만 넓힙니다
- **포즈 시계열 저장** — [D-09](../05-결정/stack/D-09-serialization.md) Protobuf. 1-D가 무엇을 쓸지 정한 뒤입니다
- **스윙 유형 분류** — 1-D. `Swing.kind`는 `nil`로 남습니다
- **보관함 화면** — 1-E
- **저장 공간 관리·클립 삭제** — [동시성 6.6](../02-설계/CONCURRENCY.md#66-열화-대응)의 저장 공간 정책
- **업로드와 클립 상태 머신** — [아키텍처 2.5](../02-설계/ARCHITECTURE.md#25-상태-머신), Phase 2

## 구현 선택지

### 1. `TeniVision`이 `CMReadySampleBuffer`를 직접 알 것인가

`CMReadySampleBuffer`는 **iOS 26.0+ / macOS 26.0+**입니다. 그런데 `TeniVision`은 `.multiplatform(iOS: "26.0", macOS: "15.0")`입니다 — macOS CLI(`TeniTool`)가 같은 프레임워크를 정적 링크합니다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| A. 직접 쓴다 | 동시성 6.3 스니펫 그대로 | macOS 15 빌드가 깨진다. 파일·테스트 전체에 `@available` 가드가 필요하고, macOS에서는 테스트가 **조용히 건너뛰어진다** |
| **B. `ClipFrame` 프로토콜로 추상화** | `CVPixelBuffer`는 macOS 15에도 있다 → 양 플랫폼에서 테스트가 돈다. 테스트가 가짜 프레임을 쓸 수 있다 | 간접 계층 하나 |

**채택: B.** `ClipFrame`은 `pixelBuffer`와 `seconds`만 요구합니다. `CMReadySampleBuffer` 적합은 카메라 경계(iOS 전용)에서 선언하며, 이번 범위에는 들어오지 않습니다.

> 동시성 6.3의 코드가 `CMReadySampleBuffer<CMSampleBuffer.PixelBufferContent>`라고 적었는데 **실제 API의 Content 타입은 `CVReadOnlyPixelBuffer`**입니다. 문서를 고칩니다.

### 2. 겹치는 후보를 어떻게 다루는가

재발화 간격은 0.8초인데 구간은 `preRoll` + `postRoll` = 4초입니다. **연속 스윙에서는 거의 항상 겹칩니다.**

| 선택지 | 장점 | 단점 |
|---|---|---|
| A. 후보마다 클립 하나 | 단순 | 같은 프레임을 여러 번 인코딩한다. 랠리 한 번에 클립 수십 개 |
| **B. 겹치면 한 클립으로 병합** | 인코딩 1회. `Clip.swings`가 배열인 이유가 이것이다 | 클립 길이가 가변이고 상한이 필요하다 |

**채택: B.** 스윙 시각은 **클립 시작 기준 상대초**로 `Swing.startSeconds`·`impactSeconds`·`endSeconds`에 넣습니다. 상한은 두지 않습니다 — 랠리가 끊기면 `postRoll`이 지나 자연히 닫히고, 상한을 두면 그 경계에서 스윙이 두 클립에 걸칩니다.

### 3. 언제 플러시하는가

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. `postRoll`이 지난 프레임이 들어오면** | 프레임이 구동한다 → 테스트가 시계에 의존하지 않고 결정론적이다 | 프레임이 끊기면 플러시도 멈춘다 → 세션 종료에서 처리한다 |
| B. 타이머 | 프레임이 끊겨도 닫힌다 | 테스트가 시간에 의존한다. 동시성 6.1이 "순서가 중요한 처리는 단일 Task"로 정한 경로에 타이머를 끼운다 |

**채택: A.** 세션 종료 시 `finish()`가 미완 구간을 **가진 만큼** 씁니다 — 마지막 스윙을 버리지 않습니다.

### 4. 어디에 어떤 이름으로 쓰는가

0-A의 세션 녹화본이 `URL.documentsDirectory` 루트에 `<시각>_120fps_<노출>_<거리>m.mov`로 쌓입니다. 스윙 클립을 같은 자리에 두면 구분되지 않습니다.

**채택**: `documentsDirectory/Clips/` 아래 `<yyyyMMdd-HHmmss>-<n>.mov`. `Clip.fileName`은 **basename만** 담고 디렉터리는 호출부가 쥡니다 — 앱 컨테이너 경로는 재설치마다 바뀌므로 DB에 절대경로를 넣으면 전부 깨집니다.

### 5. 코덱

[아키텍처 2.4](../02-설계/ARCHITECTURE.md#24-도메인-모델)가 영상을 HEVC로 적었지만, 그것은 **업로드·보관** 기준입니다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. H.264** | 시뮬레이터 인코더에서 확실히 돈다 → 게이트에서 검증된다 | 같은 품질에 용량이 크다 |
| B. HEVC | 용량 | 시뮬레이터 인코딩 가용성을 확인하지 못했다. 게이트가 깨지면 **검증 없이 가는 것**이 된다 |

**채택: A (H.264).** `TeniTool`의 `VideoWriter`가 같은 이유로 H.264입니다. HEVC 전환은 실기기에서 인코딩 비용을 재고 나서 별 이슈로 다룹니다.

## 완료 기준

- [ ] 후보 1개 → 클립 1개. 쓰인 프레임 수가 구간 안의 프레임 수와 같다
- [ ] 겹치는 후보 2개 → 클립 **1개**, `swings.count == 2`, 두 스윙의 시각이 클립 시작 기준 상대초다
- [ ] 떨어진 후보 2개 → 클립 2개
- [ ] 세션 시작 직후 후보(구간 하한이 음수) → 가진 프레임만 쓰고, 프레임이 0개면 **클립을 만들지 않는다**
- [ ] 세션 종료 시 `postRoll`을 못 채운 구간도 쓰인다
- [ ] 쓴 `.mov`를 `AVAsset`으로 다시 열어 트랙 길이와 프레임 수가 기대값과 일치한다
- [ ] 저장 후 `SessionRepository.load(id:)`가 같은 클립·스윙을 돌려준다
- [ ] `scripts/verify-ios.sh` 통과, 이 PR이 늘린 경고 0
- [ ] 뮤테이션 4건 전부 사망 (아래)

### 뮤테이션

의도적으로 망가뜨려 테스트가 잡는지 확인합니다.

| # | 변형 | 잡아야 할 테스트 |
|---|---|---|
| 1 | 병합 조건을 `겹침` → `항상 새 클립` | 겹치는 후보 2개 |
| 2 | 상대초 변환을 지우고 절대 시각을 넣는다 | 상대초 단정 |
| 3 | `finish()`가 미완 구간을 버린다 | 세션 종료 |
| 4 | 플러시 기준을 `postRoll` → `0` | 프레임 수 단정 |

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/verify-ios.sh` |
| 프레임 입력 | 합성 `CVPixelBuffer` — 카메라 없이 만든다. 각 프레임에 시각을 붙여 넣는다 |
| 쓰기 결과 | `AVAsset`으로 다시 열어 `duration`·프레임 수를 읽는다. "오류 없이 끝났다"로 통과시키지 않는다 |
| 영속화 | 인메모리 SwiftData 컨테이너에 저장 → 재조회 |
| 실시간 비용 | **미수행** — 실기기 |

## 영향받는 문서

- [동시성 6.3](../02-설계/CONCURRENCY.md) — `CMSampleBuffer.PixelBufferContent` → `CVReadOnlyPixelBuffer` 정정
- [아키텍처 2.3](../02-설계/ARCHITECTURE.md) — 구현된 범위 표시
- [INDEX](../INDEX.md) — 이 문서 등재

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| **캡처 풀 고갈** — 동시성 6.3이 "픽셀을 복사하지 않는다"고 정했는데, 링 버퍼는 5초를 **붙잡고** 있다. 1080p120이면 600프레임이다 | 프레임 드롭, 최악은 세션 중단. 시뮬레이터에서는 드러나지 않는다 | 이번에는 버퍼 창을 프로필에서 받아 줄일 수 있게만 둔다. 실측은 실기기 |
| 실시간 인코딩 비용 미측정 | 발열·드롭 | 미수행으로 남긴다 |
| 쓰기가 느려 플러시가 밀린다 | 링 버퍼가 더 쌓인다 | `ClipWriter`는 `actor` 바깥에서 돌리지 않는다 — 순서를 지키고, 밀리면 밀린 채로 끝낸다. 프레임을 버리는 정책은 실측 뒤 |
| 저장 공간 | 클립이 무한히 쌓인다 | 범위 밖. 동시성 6.6이 정책을 들고 있고 별 이슈로 다룬다 |

## 미수행으로 남길 것

- **실기기** — 실시간 인코딩 비용, 캡처 풀 고갈, 발열. 자동화할 수 없습니다
- **카메라 배선** — `AVCaptureVideoDataOutput` + 포즈 검출. 그것이 없으면 **라이브 카메라에서는 이 경로가 한 번도 돌지 않습니다**
- **HEVC 전환** — 실기기 측정 뒤
- **저장 공간 관리·클립 삭제**

## 관련 문서

- [SPEC-0085 스윙 트리거](SPEC-0085-swing-trigger.md)
- [SPEC-0070 1-B 기반](SPEC-0070-persistence-foundation.md)
- [아키텍처](../02-설계/ARCHITECTURE.md) · [동시성](../02-설계/CONCURRENCY.md)
- [D-08 로컬 DB](../05-결정/stack/D-08-local-db.md) · [D-09 직렬화](../05-결정/stack/D-09-serialization.md)

---

[← 문서 허브](../INDEX.md)
