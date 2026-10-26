---
title: "SPEC-0107 발열·시스템 압력 대응"
aliases: ["SPEC-0107", "발열 시스템 압력 대응"]
tags:
  - 문서유형/기획
  - 영역/UI
issue: 107
type: feature
area: ui
created: 2026-10-26
updated: 2026-10-26
status: active
---

# SPEC-0107. 발열·시스템 압력 대응

> 이슈 [#107](https://github.com/wnsgur9137/TeniTeni/issues/107)

## 배경

[제품 개요](../01-제품/PRODUCT-OVERVIEW.md)가 "연속 15분 촬영 시 스로틀링 없음"을 요구한다. 그래도 넘으면 **조용히 느려지는 것이 가장 나쁘다** — 사용자는 계속 치고 있는데 기록이 빠진다.

지금은 발열·압력을 **아무도 보지 않는다.** `ProcessInfo.thermalState`도 `AVCaptureDevice.SystemPressureState`도 코드에 참조가 0이다. 120fps 촬영이 기본 권장값이므로([촬영 프로토콜 5.2](../02-설계/CAPTURE-PROTOCOL.md)) 실기기에서 가장 먼저 만날 한계다.

## 설계 충돌을 먼저 해소했다

두 문서가 **서로 다른 신호에 서로 다른 조치**를 지정하고 있었다.

| | `.serious` | `.critical` |
|---|---|---|
| [IA-FLOW](../06-디자인/IA-FLOW.md) (`ProcessInfo.thermalState`) | 테두리 주황 + "120→60 낮출까요" **제안** | 테두리 빨강 + 경고음 + **녹화 중단** |
| [CONCURRENCY 6.6](../02-설계/CONCURRENCY.md) (`SystemPressureState`) | **고지 없음** — 데시메이션만 강화 | **fps 자동 강등** + 고지 필수 |

**정본은 CONCURRENCY 6.6이다.** 근거 둘:

1. 압력이 과도해지면 **캡처 시스템이 세션을 스스로 종료한다.** 묻고 답을 기다리는 사이에 그게 벌어진다
2. 사용자는 **6m 밖 코트에 있다.** 다이얼로그에 답할 수 없고, 답하러 다가오면 촬영이 끊긴다

IA-FLOW의 발열 표와 `ThermalWarning` 목업을 이 기준으로 고쳤다. 이 결정은 [DECISION-LOG](../05-결정/DECISION-LOG.md)에도 남긴다.

## 범위

### 만들 것

- `AVCaptureDevice.systemPressureState` KVO 관측
- 수준 → 조치 매핑을 **값으로** 분리 — 실기기 없이 전수 검증된다
- `.serious`: 포즈 데시메이션 강화. **화면에 아무것도 띄우지 않는다**
- `.critical`: fps 120 → 60 **자동 강등** + 사후 고지("60fps로 낮췄습니다")
- `.shutdown`: 세션 중단 경로 재사용([#100](https://github.com/wnsgur9137/TeniTeni/issues/100))
- `.fair` 이하로 회복되면 **원래 설정으로 복귀**하고 그 시점을 남긴다
- **클립마다 그때의 실제 fps를 기록한다** — 한 세션이 강등을 걸치면 클립의 fps가 서로 다르다

### 만들지 않을 것

- `ProcessInfo.thermalState` 경로 — 정본이 아니다
- 저조도·흔들림·저장공간 열화(`Degradation`의 나머지)
- 경고음 — "판정 불가를 코트에서 어떻게 말할 것인가"가 아직 미결이다(IA-FLOW 10.5)
- `EmptySession`·`QuickCheck` 화면

## 구현 선택지

### 1. 강등된 fps를 어디에 기록하는가

`Session.fps`는 하나이고 `Clip.fps`도 하나다. 한 세션이 강등을 걸치면 둘 중 하나는 거짓이 된다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| 세션의 `fps`를 강등값으로 덮는다 | 단순 | 강등 전 클립이 **60fps로 기록된다** — 분석이 프레임 간격을 잘못 가정한다 |
| `Session`에 강등 이력을 넣는다 | 완전한 기록 | 엔티티·스키마 변경. 이 작업 범위를 넘는다 |
| **클립마다 그때의 실제값을 쓴다** | `Clip.fps`가 이미 있다. 거짓이 생기지 않는다 | `SessionBuilder.add`가 fps를 함께 받아야 한다 |

**채택**: 클립마다 실제값. `Session.fps`는 **시작 시점의 실제값**으로 남고, 강등 사실은 클립의 fps 차이로 드러난다.

### 2. 데시메이션 강화를 어떻게 넣는가

| 선택지 | 장점 | 단점 |
|---|---|---|
| `FrameDecimator`의 `analysisFPS`를 낮춘다 | 이미 있는 손잡이다. 상한 계산이 한 곳에 남는다 | 없음 |
| 인테이크에 별도 배수를 둔다 | — | 간격 계산이 두 곳으로 갈린다 |

**채택**: `analysisFPS`를 낮춘다(60 → 30). 간격은 `FrameDecimator`가 계속 혼자 정한다.

## 완료 기준

- [ ] 수준 → 조치 매핑이 **카메라 없이** 전수 검증된다
- [ ] `.serious`에서 화면에 아무것도 띄우지 않는다
- [ ] `.critical`에서 fps가 강등되고 **그 뒤 클립의 fps가 실제값**이다
- [ ] `.fair` 이하로 회복되면 원래 설정으로 돌아간다
- [ ] `.shutdown`은 중단 경로로 간다
- [ ] 클린 빌드 경고 **0**
- [ ] IA-FLOW·CONCURRENCY·캔버스가 서로 어긋나지 않는다

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `DEVELOPER_DIR=… CLEAN_BUILD=1 ./scripts/verify-ios.sh` |
| 문서 게이트 | `./scripts/verify-docs.sh` |
| 수준 → 조치 | `PresentationTests` — 값 매핑 전수 |
| 클립 fps | `PresentationTests` — 강등 전후 프레임을 흘려 저장된 클립의 fps를 본다 |
| 테스트가 의미 있는가 | 뮤테이션 — `.serious`를 고지하게, 강등값을 요청값으로, 회복을 생략 |

## 영향받는 문서

- [IA-FLOW.md](../06-디자인/IA-FLOW.md) — 발열 표를 정본에 맞춘다. `ThermalWarning` 행의 트리거를 `.critical`로
- [CONCURRENCY.md](../02-설계/CONCURRENCY.md) 6.6 — 정본임을 명시
- [DECISION-LOG.md](../05-결정/DECISION-LOG.md) — 충돌 해소 결정
- `docs/06-디자인/_canvas/ThermalWarning.dc.html` — 제안(버튼 2개) → 사후 고지
- [INDEX.md](../INDEX.md) — 이 문서 등재

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| 강등과 복귀가 번갈아 일어난다 | fps가 흔들려 클립마다 값이 다르다 | 복귀는 `.fair` **이하**에서만 — 히스테리시스가 수준 사이에 이미 있다 |
| KVO가 메인에서 오지 않는다 | 격리 위반 | 관측 클로저에서 값만 꺼내 메인으로 넘긴다(#100과 같은 모양) |
| 강등이 세션 중간에 일어난다 | 분석이 프레임 간격을 잘못 가정한다 | 선택지 1 — 클립마다 실제값 |

## 미수행으로 남길 것

- **실제 발열 재현** — 장시간 120fps 촬영이 필요하다. 시뮬레이터에는 압력 상태가 없다
- **데시메이션 강화가 실제로 열을 낮추는지** — 실기기 측정
- KVO 등록·해제 자체 — 세션 없이 압력 변화를 쏠 수 없다

## 관련 문서

- [02. 동시성 설계](../02-설계/CONCURRENCY.md) 6.6
- [06. IA·플로우](../06-디자인/IA-FLOW.md)
- [SPEC-0097 스윙 검출 배선](SPEC-0097-swing-wiring.md)
- [SPEC-0096 카메라 프레임을 포즈로](SPEC-0096-pose-intake.md)

---

[← 문서 허브](../INDEX.md)
