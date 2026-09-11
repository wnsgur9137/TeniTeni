---
title: "SPEC-0005 TeniVision 모듈 분리"
aliases: ["SPEC-0005", "TeniVision 모듈 분리"]
tags:
  - 문서유형/기획
  - 영역/비전
issue: 5
type: "♻️Refactor"
area: "🧩Core"
created: 2026-09-11
updated: 2026-09-11
status: active
---

# SPEC-0005. TeniVision 모듈 분리

> 이슈 [#5](https://github.com/wnsgur9137/TeniTeni/issues/5) · 마일스톤 `0-C 검증`

## 배경

0-C의 오프라인 검증 도구(#7 CLI, #8 라벨링, #9 스윙)는 **macOS에서 돌면서 iOS 앱과 같은 분석 코드를 써야** 합니다. 지금은 단일 타깃이라 공유가 불가능합니다.

모듈 분리 시점을 0-C로 잡은 것도 이 이유입니다 — [작업 순서 9.6](../04-계획/WORK-PLAN.md)의 "필요할 때 만든다" 원칙.

관련 결정은 [D-05 모듈 빌드 도구](../05-결정/stack/D-05-module-tooling.md)와 [작업 순서 9.6](../04-계획/WORK-PLAN.md)에 있습니다. 여기서 재론하지 않습니다.

### 착수 전 해소한 미확인 항목

**Tuist가 하나의 타깃을 iOS + macOS 양쪽으로 만들 수 있는가** — ✅ 확인됨.

`destinations: [.iPhone, .mac]` + `deploymentTargets: .multiplatform(iOS:macOS:)`로 단일 타깃이 양쪽 빌드에 성공했고, `DetectTrajectoriesRequest`도 양쪽에서 컴파일됩니다. **소스를 공유하는 별도 타깃 2개로 갈 필요가 없습니다.**

## 범위

### 만들 것

- `ios/Projects/TeniVision` Tuist 모듈 (`destinations: [.iPhone, .mac]`, 프레임워크)
- 앱 타깃이 이 모듈에 의존
- UI에 의존하지 않는 기존 소스 4개를 이동
  - `CaptureSettings.swift` — 값 타입 (품질·노출·거리)
  - `ClipMetadata.swift` — 클립 메타 + 공 크기 계산
  - `FormatSelector.swift` — 포맷 선택 로직
  - `FormatReport.swift` — 포맷 리포트 모델 + 공 크기 계산
- **공 크기 계산식 단일화** — 현재 `ClipMetadata`와 `FormatReport`에 같은 식이 중복 구현되어 있다
- `FormatInspector`의 플랫폼 의존 제거 (아래 참고)

### 만들지 않을 것

- **Pose / Ball / Render / Swing / Metrics 실제 구현** — 0-D 이후 작업. 지금은 빈 디렉터리도 만들지 않는다
- **`Core` 모듈** — [작업 순서 9.6](../04-계획/WORK-PLAN.md)에서 0-D 도입으로 잡혀 있다
- **macOS CLI 도구 자체** — 이슈 [#7](https://github.com/wnsgur9137/TeniTeni/issues/7)
- **Domain / Data / Presentation 분리** — 1-A 작업
- 촬영 화면·인스펙터 화면의 UI 코드 이동 (SwiftUI 의존이므로 앱에 남는다)

## 구현 선택지

### `FormatInspector`의 플랫폼 의존을 어떻게 끊을 것인가

`FormatInspector.deviceInfo()`가 `UIDevice.current.systemName` / `.systemVersion`을 씁니다. UIKit 의존이라 macOS에서 컴파일되지 않습니다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. `ProcessInfo`로 교체** | 양 플랫폼 공통 API. 조건부 컴파일 불필요 | 표기가 `UIDevice`와 미묘하게 다름 |
| B. `#if os(iOS)` 분기 | 기존 표기 유지 | 조건부 컴파일이 늘어나고 macOS 경로가 검증되지 않음 |
| C. 인스펙터를 앱에 남김 | 이동 안 해도 됨 | 0-C CLI가 포맷 리포트를 못 읽음 — **목적에 반함** |

**채택: A.** `ProcessInfo.processInfo.operatingSystemVersionString`은 양쪽에서 동작하고, `DeviceIdentifier`(utsname)는 이미 플랫폼 중립입니다. 조건부 컴파일이 없는 쪽이 macOS 경로가 실제로 검증됩니다.

### 모듈 내부 디렉터리 구조

| 선택지 | 내용 |
|---|---|
| **A. 최소 — `Capture/` `Format/` 두 개** | 지금 이동할 것만 담는다 |
| B. 최종 구조 미리 생성 | `Pose/ Ball/ Render/ Swing/ Metrics/`를 빈 채로 |

**채택: A.** 빈 디렉터리는 "여기 뭔가 있어야 한다"는 착시를 줍니다. 0-D에서 실제로 만들 때 추가합니다.

## 완료 기준

- [x] `ios/Projects/TeniVision/Project.swift` 존재, `destinations: [.iPhone, .mac]`
- [x] 앱 타깃이 `TeniVision`에 의존하고 `import TeniVision`으로 사용
- [x] `TeniVision`이 SwiftUI·UIKit을 import하지 않음 (grep으로 확인)
- [x] iOS 시뮬레이터 빌드 성공
- [x] **macOS 빌드 성공** — 0-C CLI의 전제
- [x] 공 크기 계산식이 한 곳에만 존재 (`BallGeometry`)
- [x] `scripts/verify-ios.sh` 통과, 동시성 경고 0

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `scripts/verify-ios.sh` |
| macOS 빌드 | `xcodebuild -scheme TeniVision -destination 'platform=macOS' build` |
| UI 의존 없음 | `grep -rl "import SwiftUI\|import UIKit" ios/Projects/TeniVision` → 결과 없음 |
| 계산식 중복 | `grep -rn --include='*.swift' "0.067" ios/` → `BallGeometry.swift` 1건 |

**게이트에 macOS 빌드를 추가했습니다.** `verify-ios.sh`가 `Projects/*/Project.swift`에서 `.mac`을 선언한 모듈을 찾아 macOS로도 빌드합니다. 새 멀티플랫폼 모듈이 추가되면 스크립트 수정 없이 자동으로 포함됩니다.

## 구현 중 달라진 점

### `#if os(iOS)`를 끝까지 피할 수 없었다

선택지 A를 채택하면서 "조건부 컴파일 불필요"라고 적었지만, 실제로는 **`UIDevice` 외에도 macOS에 없는 API가 더 있었습니다.** macOS 빌드에서 드러난 것:

- `AVCaptureDevice.Format` — `isVideoBinned` · `videoFieldOfView` · `minExposureDuration` · `maxExposureDuration` · `minISO` · `maxISO` · `isVideoHDRSupported` · `videoMaxZoomFactor` 전부 iOS 전용
- `AVCaptureDevice.DeviceType` — `builtInUltraWideCamera` · `builtInTelephotoCamera` iOS 전용

`UIDevice` → `ProcessInfo` 교체(선택지 A)는 그대로 적용했고, **살아있는 캡처 기기를 훑는 코드만** `#if os(iOS)`로 감쌌습니다.

| 대상 | 플랫폼 | 이유 |
|---|---|---|
| `BallGeometry` · `ClipMetadata` · `CaptureSettings` · `FormatReport` | iOS + macOS | 순수 값·계산. 0-C CLI가 쓰는 것들 |
| `FormatInspector.export` · `DeviceIdentifier` · `deviceInfo` | iOS + macOS | JSON 인코딩 · `utsname` |
| `FormatInspector.makeReport` 및 기기 탐색 | iOS only | 캡처 기기 포맷 속성이 macOS에 없음 |
| `FormatSelector` | iOS only | `activeFormat` 선택은 실기기 전용 개념 |

**0-C CLI는 손해를 보지 않습니다.** CLI는 이미 찍힌 영상과 앱이 내보낸 `FormatReport` JSON을 다루므로, 필요한 것은 디코딩 가능한 데이터 모델과 계산식이고 그쪽은 전부 양 플랫폼 공용입니다.

### 공 크기 계산식을 `BallGeometry`로 뽑았다

기획서에는 "단일화"만 적었고 어디에 둘지는 정하지 않았습니다. `ClipMetadata`·`FormatReport` 어느 쪽에 두어도 다른 쪽이 그것을 참조해야 하므로, 독립 타입 `BallGeometry`를 만들고 양쪽이 위임하게 했습니다.

추가로 `ClipMetadata`의 memberwise initializer를 **`estimatedBallPixelDiameter`를 받지 않는 `public init`으로 교체**했습니다. 호출자가 직접 넘기면 저장값이 계산식과 어긋날 수 있는데, 이 값은 0-C에서 실측과 비교하는 기준이라 어긋나면 검증 자체가 무의미해집니다.

### 워크스페이스를 새로 만들었다

모듈이 2개가 되었으므로 `ios/Workspace.swift`가 필요합니다. 기획서에는 없던 항목입니다.

## 영향받는 문서

- [iOS 기술 스택](../03-기술스택/IOS-STACK.md) — 모듈 구조에 `destinations` 명시
- [작업 순서](../04-계획/WORK-PLAN.md) — 9.6 미확인 항목 해소 기록
- `scripts/verify-ios.sh` — macOS 빌드 단계 추가 (완료)
- [동시성 설계](../02-설계/CONCURRENCY.md) — 0-D actor 배치 시 `TeniVision` 경계를 전제로 함

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| macOS 빌드가 CI에서 실패 | 0-C 착수 불가 | 게이트에 macOS 빌드를 넣어 매 PR에서 검증 (적용 완료) |
| `#if os(iOS)` 블록이 늘어나 macOS 경로가 검증 사각으로 남음 | 0-C에서 늦게 발견 | 게이트가 매번 macOS를 빌드하므로 컴파일 수준은 막힌다. 런타임 차이는 0-C CLI 착수 시 확인 |
| 프레임워크 분리로 빌드 시간 증가 | 개발 속도 | 모듈 1개 수준에서는 무시 가능. 1-A에서 재평가 |
| `ProcessInfo` 표기가 기존과 달라 리포트 비교 불가 | 0-A 실측 데이터와 불일치 | 아직 실측 데이터가 없으므로 지금 바꾸는 것이 안전 |
| `systemName`을 `#if`로 직접 만들어 `UIDevice`와 표기가 갈릴 수 있음 | 리포트 필드 해석 혼란 | iOS에서 `"iOS"` 고정 — `UIDevice.current.systemName`과 같은 값이다 |

## 미수행으로 남길 것

- **실기기 검증** — 모듈 분리는 빌드 구조 변경이므로 시뮬레이터·macOS 빌드로 충분하나, 인스펙터의 `ProcessInfo` 표기가 실기기에서 어떻게 나오는지는 [#4](https://github.com/wnsgur9137/TeniTeni/issues/4)에서 확인
- **단위 테스트** — 이동한 계산식(공 크기)에 테스트를 붙일 수 있으나, 골든 테스트 기반이 0-C에서 갖춰지므로 그때 함께 넣는다

## 관련 문서

- [작업 순서 9.6](../04-계획/WORK-PLAN.md)
- [D-05 모듈 빌드 도구](../05-결정/stack/D-05-module-tooling.md)
- [촬영 프로토콜](../02-설계/CAPTURE-PROTOCOL.md)

---

[← 문서 허브](../INDEX.md)
