---
title: "스포츠 영상 이벤트 라벨링"
aliases: ["이벤트 라벨링", "Action Spotting", "어노테이션"]
tags:
  - 문서유형/레퍼런스
  - 영역/비전
researched: 2026-09-11
created: 2026-09-11
updated: 2026-09-11
status: active
---

# 스포츠 영상 이벤트 라벨링

> 게이트의 **분모**를 사람이 만든다. 그 분모가 얼마나 정확할 수 있는지가 게이트 기준의 타당성을 결정한다.

이슈 [#8](https://github.com/wnsgur9137/TeniTeni/issues/8) 착수 전 조사.

## 1. Action Spotting — 우리가 하는 것의 이름

스포츠 영상 이벤트 라벨링은 두 갈래다.

| 방식 | 내용 |
|---|---|
| **Action Spotting** | **단일 타임스탬프**로 이벤트를 표현 |
| Interval annotation | 시작·종료 구간을 표시 |

Spotting은 "빠르고 겹치고 연속적인 스포츠 이벤트에 특히 유용"하다고 평가된다. 라벨링을 단순화하고 모호함을 없앤다.

**우리 임팩트 프레임이 정확히 Action Spotting이다.** 구간이 아니라 점이다. 이 선택은 이미 [프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md)가 했고, 문헌의 주류와 일치한다.

### 테니스 데이터셋이 이미 같은 개념을 쓴다

기존 테니스 데이터셋(25·30 fps)은 프레임 단위 이벤트를 6개 클래스로 나눈다. 그중 둘이 우리와 직결된다.

- `player serve ball contact` — 서브 임팩트
- `regular swing ball contact` — 일반 스윙 임팩트
- `ball bounce` — 바운드

**우리의 "임팩트 프레임"은 이 둘을 합친 것이다.** 1-B 스윙 검출에서 서브와 일반 스윙을 갈라야 할 때 이 분류를 참고할 수 있다.

## 2. ⚠️ 우리 허용오차가 문헌 표준보다 4배 엄격하다

문헌의 품질 기준:

> 경계 타임스탬프의 어노테이터 간 일치를 감시하며, **30 fps에서 평균 절대 경계 차이 3프레임 미만**을 목표로 한다.

환산하면:

| 기준 | 프레임 | 시간 |
|---|---|---|
| 문헌 (30 fps) | ±3 | **100 ms** |
| **우리 (120 fps)** | **±3** | **25 ms** |

**우리 [프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md)의 ±3프레임은 120 fps 기준이므로 25 ms다.** 문헌 표준의 1/4이다.

### 왜 문제인가

게이트 검출률의 분모는 **사람이 센 타구**다. 사람이 임팩트 프레임을 25 ms 안으로 찍지 못하면, **검출기가 정확해도 매칭이 실패해 검출률이 낮게 나온다.** 도구를 탓하게 된다.

관련 수치:

- Charades의 인간 어노테이터 간 temporal IoU는 **72.5 %**, MultiTHUMOS는 58.7 %
- AVA 데이터셋은 시작·종료를 **±0.5초** 정밀도로 본다
- 최근 벤치마크의 시작 시각 편차 평균 **0.4초**

### 다만 임팩트는 "경계"가 아니다

위 수치들은 **액션 경계**(언제 달리기가 시작되는가)에 대한 것이다. 경계는 본질적으로 모호하다.

**라켓-공 접촉은 순간 이벤트다.** 공이 라켓에 닿는 프레임은 보면 안다 — 특히 120 fps에서는 접촉 전후가 시각적으로 뚜렷이 다르다. 위 수치를 그대로 적용할 수 없다.

**그러나 확인되지 않았다.** 우리 영상에서 사람이 얼마나 정확히 찍는지는 재봐야 안다.

### 대응 — 도구가 스스로 재게 한다

같은 클립을 **두 번 라벨링해 자기 일치도(self-agreement)를 재면** ±3프레임이 현실적인지 데이터로 알 수 있다. 두 번의 차이가 3프레임을 넘으면 기준을 넓혀야 한다.

이것을 [#8](https://github.com/wnsgur9137/TeniTeni/issues/8)의 범위에 넣는다. 게이트 기준 자체를 바꾸는 것은 별개 판단이다.

## 3. #8에 반영할 것

- **Action Spotting 방식** — 단일 프레임 번호. 구간이 아니다 (이미 프로토콜이 정함)
- **자기 일치도 측정** — 같은 클립 재라벨링 후 프레임 차이 산출
- 출력은 `teni analyze`의 `--ground-truth`가 읽는 포맷

## 4. 확인하지 못한 것

- **실제 라벨링 도구의 UX** — CVAT·VIA 같은 도구의 단축키·조작 관행은 찾지 못했다. 학술 자료는 데이터셋과 방법론 중심이다
- **테니스 임팩트의 실제 어노테이터 일치도** — 위 수치는 일반 액션 경계다. 임팩트 전용 수치는 못 찾았다
- **120 fps에서 사람이 얼마나 정확한가** — 우리가 직접 재야 한다

## 관련 문서

- [촬영 프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md) — 측정 정의와 ±3프레임 기준
- [DetectTrajectoriesRequest API](DetectTrajectories.md)
- [레퍼런스 허브](../INDEX.md)

## 출처

- [Action Spotting and Precise Event Detection in Sports](https://arxiv.org/html/2505.03991v1)
- [Spotting Temporally Precise, Fine-Grained Events in Video](https://arxiv.org/pdf/2207.10213)
- [SoccerNet-v2](https://arxiv.org/pdf/2011.13367)
- [AVA: A Video Dataset of Spatio-temporally Localized Atomic Visual Actions](https://openaccess.thecvf.com/content_cvpr_2018/papers/Gu_AVA_A_Video_CVPR_2018_paper.pdf)

---

[← 문서 허브](../../INDEX.md)
