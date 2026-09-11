---
title: "SPEC-0007 macOS CLI 궤적 분석 도구"
aliases: ["SPEC-0007", "teni analyze"]
tags:
  - 문서유형/기획
  - 영역/비전
issue: 7
type: "✨Feature"
area: "🧠ML"
created: 2026-09-11
updated: 2026-09-11
status: active
---

# SPEC-0007. macOS CLI 궤적 분석 도구

> 이슈 [#7](https://github.com/wnsgur9137/TeniTeni/issues/7) · 마일스톤 `0-C 검증`

## 배경

영상에 `DetectTrajectoriesRequest`를 돌려 검출 결과를 [촬영 프로토콜 5.5](../02-설계/CAPTURE-PROTOCOL.md)의 포맷으로 내보냅니다. **Phase 0 게이트 판정의 측정 도구**입니다.

[#6](https://github.com/wnsgur9137/TeniTeni/issues/6)이 정답을 아는 합성 영상을 만들었으므로, 이 도구가 맞게 동작하는지 판정할 수 있습니다. 실기기 없이 검증되는 경로입니다.

CLI 배치는 [SPEC-0006](SPEC-0006-synthetic-video.md)이 정했습니다 — `teni` 단일 실행 파일의 서브커맨드.

착수 전 조사는 [DetectTrajectoriesRequest API](../08-레퍼런스/ml/DetectTrajectories.md)에 있습니다. 설계를 좌우한 세 가지:

- **`StatefulRequest`다.** 인스턴스를 프레임마다 새로 만들면 상태가 날아가 궤적이 절대 확정되지 않습니다
- **`timeRange`와 `uuid`가 `TrajectoryObservation` 문서 페이지에 없습니다.** `VisionObservation` 프로토콜에서 옵니다. 없는 줄 알면 프레임을 직접 세게 됩니다
- **`CMSampleBuffer`로 먹여야 `timeRange`가 나옵니다.** `CGImage`로 변환하면 타임스탬프가 사라집니다

## 범위

### 만들 것

- `teni analyze` 서브커맨드
- `AVAssetReader`로 프레임을 순차 읽어 **하나의 요청 인스턴스**에 공급
- `uuid` 기준 중복 제거 — 궤적 하나를 한 번만 센다
- `--ground-truth`가 주어지면 **임팩트 프레임 ±3 매칭** 후 검출률 산출
- 프로토콜 5.5 포맷 JSON 출력

### 만들지 않을 것

- **파라미터 스윕·조건별 집계** — [#9](https://github.com/wnsgur9137/TeniTeni/issues/9)입니다. 이 도구는 **클립 하나**를 분석합니다
- **임팩트 프레임 수동 라벨링** — [#8](https://github.com/wnsgur9137/TeniTeni/issues/8)
- **포즈 검출** — 0-D
- **게이트 판정 출력** — 70%/50% 판정은 #9가 여러 조건을 모아 내립니다. 이 도구는 클립 하나의 검출률까지입니다
- **실영상 최적화** — 합성 영상으로 도구가 동작함을 보이는 데까지입니다

## 구현 선택지

### 1. 프레임 공급 방식

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. `AVAssetReader` → `CMSampleBuffer` 그대로** | **타임스탬프가 보존돼 `timeRange`가 나온다.** 변환 비용 0 | 픽셀 포맷을 요청에 맞춰야 한다 |
| B. `AVAssetImageGenerator` → `CGImage` | 프레임 접근이 단순 | **`timeRange`가 `nil`이 된다.** 프레임을 직접 세야 하고 그 계산이 틀리면 매칭이 전부 어긋난다 |

**채택: A.** B는 API가 주는 정보를 버리고 직접 재구성하는 것입니다.

### 2. 중복 궤적 처리

`StatefulRequest`는 프레임마다 관측을 냅니다. 같은 궤적이 갱신되며 여러 번 보고됩니다.

| 선택지 | 내용 |
|---|---|
| **A. `uuid`로 묶고 마지막 관측을 채택** | 점이 가장 많이 쌓인 상태가 마지막이다 |
| B. 첫 관측 채택 | `trajectoryLength` 최소 점수만 모인 시점 — 정보가 적다 |
| C. 전부 기록 | 한 타구를 여러 번 세어 검출률이 부풀려진다 |

**채택: A.** 단, **`uuid`가 궤적 수명 동안 유지되는지 확인되지 않았습니다** — 합성 영상으로 검증합니다. 유지되지 않으면 `timeRange` 겹침으로 묶는 대안을 씁니다.

### 3. 임팩트 매칭 기준

[프로토콜 5.5](../02-설계/CAPTURE-PROTOCOL.md)가 이미 정했습니다 — **임팩트 프레임 ±3프레임 내에 시작하고 0.2초 이상 이어진 궤적.** 재론하지 않고 그대로 구현합니다.

한 임팩트에 여러 궤적이 걸리면 **가장 가까운 것 하나만** 매칭합니다. 나머지는 오검출로 셉니다 — 그러지 않으면 검출률이 부풀려집니다.

## 완료 기준

- [ ] `teni analyze --help`가 파라미터 목록을 출력
- [ ] 합성 영상(`teni synth` 출력)을 입력받아 JSON 생성
- [ ] 출력이 [프로토콜 5.5](../02-설계/CAPTURE-PROTOCOL.md) 포맷과 키가 일치
- [ ] `--ground-truth` 없이도 검출 목록만 내보낼 수 있음
- [ ] `--ground-truth`가 있으면 `matchedImpact`·`detectionRate`·`falsePositives` 산출
- [ ] **요청 인스턴스를 재사용** — 프레임마다 새로 만들지 않음 (테스트로 고정)
- [ ] `scripts/verify-ios.sh` 통과, 경고 0

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `scripts/verify-ios.sh` |
| 매칭 로직 | 합성 정답과 인위적 검출 결과를 넣어 ±3 경계·0.2초 경계를 단위 테스트로 고정 |
| 중복 제거 | 같은 `uuid` 관측 여러 개 → 1건으로 집계되는지 |
| **실제 검출** | `teni synth`로 만든 1/1000s 영상을 분석해 검출이 일어나는지 |

마지막 항목이 이 작업의 진짜 시험대입니다. **검출이 0건이어도 도구 실패가 아닙니다** — 그 자체가 Phase 0 게이트가 재려는 값입니다. 다만 합성 영상은 배경이 균일해 실영상보다 쉬우므로, **0건이면 도구 쪽을 먼저 의심**해야 합니다.

## 영향받는 문서

- [비전 파이프라인](../02-설계/VISION-PIPELINE.md) — 관측 멤버 표 추가 (완료)
- [작업 순서](../04-계획/WORK-PLAN.md) — 0-C 2번 항목

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| **합성 영상에서 검출이 0건** | 도구가 맞는지 영상이 문제인지 모름 | 파라미터(`objectMinimum/MaximumNormalizedRadius`)를 넓혀 재시도. 공 지름 15.31px는 정규화 반지름 약 0.004로 초기값 범위 안이다 |
| `uuid`가 유지되지 않음 | 중복 제거 실패 → 검출률 부풀려짐 | `timeRange` 겹침으로 묶는 대안. 선택지 2 참고 |
| `timeRange`가 기대와 다른 것을 담음 | `startFrame` 계산이 어긋남 | 합성 정답과 대조하면 즉시 드러난다 |
| 합성 영상이 쉬워서 낙관적 결과 | 게이트 오판 | **게이트 판정에 합성을 쓰지 않는다** — SPEC-0006이 이미 못 박았다 |

## 미수행으로 남길 것

- **실영상 분석** — 0-B 촬영 후
- **게이트 판정** — #9
- **검출률의 의미 해석** — 합성 영상의 검출률은 도구 동작 확인용이지 게이트 값이 아닙니다

## 관련 문서

- [DetectTrajectoriesRequest API](../08-레퍼런스/ml/DetectTrajectories.md) — 착수 전 조사
- [촬영 프로토콜 5.5](../02-설계/CAPTURE-PROTOCOL.md) — 측정 정의와 기록 포맷
- [비전 파이프라인](../02-설계/VISION-PIPELINE.md) — 파라미터 초기값
- [SPEC-0006 합성 영상 생성기](SPEC-0006-synthetic-video.md)

---

[← 문서 허브](../INDEX.md)
