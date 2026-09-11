---
title: "검출 평가 지표"
aliases: ["검출률", "precision", "recall", "평가 지표"]
tags:
  - 문서유형/레퍼런스
  - 영역/비전
researched: 2026-09-11
created: 2026-09-11
updated: 2026-09-11
status: active
---

# 검출 평가 지표

> Phase 0 게이트가 무엇을 재고 **무엇을 안 재는지**.

이슈 [#9](https://github.com/wnsgur9137/TeniTeni/issues/9) 착수 전 조사.

## 1. 우리 용어를 표준으로 옮기면

[프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md)의 정의를 표준 지표와 대조했습니다.

| 우리 이름 | 정의 | 표준 이름 |
|---|---|---|
| **검출률** | 매칭된 타구 ÷ 실제 타구 | **Recall** |
| **오검출률** | 무관 궤적 ÷ 전체 검출 궤적 | **1 − Precision** |

같은 것을 다르게 부르고 있습니다. 표준 정의:

- **Precision** = TP ÷ (TP + FP) — 검출한 것 중 맞은 비율. 낮으면 **헛것을 많이 잡는다**
- **Recall** = TP ÷ (TP + FN) — 실제 중 잡은 비율. 낮으면 **놓친다**
- **F1** = precision과 recall의 조화평균

## 2. ⚠️ 게이트가 recall만으로 판정한다

[프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md)의 판정표는 **검출률(recall)만** 봅니다.

| 결과 | 조치 |
|---|---|
| 검출률 ≥ 70 % | ✅ 게이트 통과 |
| 50 ~ 70 % | ⚠️ 튜닝 후 재측정 |
| < 50 % | ❌ 접근 재설계 |

오검출은 기록 포맷(`falsePositives`)에 있지만 **판정에는 들어가지 않습니다.**

### 왜 문제인가

`objectMaximumNormalizedRadius`를 크게 잡고 `trajectoryLength`를 최소로 두면 recall이 올라갑니다. 대신 배경 움직임·그림자·다른 선수까지 궤적으로 잡습니다.

**recall 75 %, precision 20 %인 설정이 게이트를 통과합니다.** 타구 하나에 헛검출 4개가 붙는다는 뜻이고, 실사용에서는 쓸 수 없습니다. 그런데 게이트는 "통과"라고 말합니다.

파라미터 스윕은 이 방향으로 몰아갑니다 — **판정 기준이 recall이면 recall을 최대화하는 설정이 "최적"으로 뽑힙니다.**

### 대응

[#9](https://github.com/wnsgur9137/TeniTeni/issues/9)는 **precision·recall·F1을 전부 산출**하되 **판정은 프로토콜대로 recall로** 합니다. precision이 낮으면 경고를 냅니다.

**기준을 바꾸지 않습니다.** 게이트 판정 기준을 도구가 바꾸면 안 됩니다 — 드러내기만 하고 결정은 사람이 합니다. [#8](https://github.com/wnsgur9137/TeniTeni/issues/8)의 자기 일치도와 같은 원칙입니다.

## 3. 우리 상황의 특수성

일반 물체 검출과 다른 점이 있습니다.

| 항목 | 일반 검출 | 우리 |
|---|---|---|
| 매칭 기준 | IoU (바운딩 박스 겹침) | **시간 근접** (임팩트 ±3프레임) |
| TN | 정의됨 | **없음** — "타구가 아닌 프레임"을 세지 않는다 |
| 대상 수 | 프레임당 여럿 | 클립당 수십 (타구) |

TN이 없으므로 **accuracy와 FPR은 계산할 수 없습니다.** precision·recall·F1만 의미가 있습니다.

## 4. #9에 반영할 것

- precision·recall·F1을 조건별로 산출
- **판정은 recall 기준** (프로토콜 5.5 그대로)
- precision이 낮은 설정에 경고
- accuracy·FPR은 내지 않는다 — TN이 없어 정의되지 않는다

## 5. 확인하지 못한 것

- **스포츠 event spotting의 관례적 precision 하한** — 찾지 못했습니다. 어느 정도가 "쓸 만한가"는 우리가 정해야 합니다
- **실영상에서의 오검출 양상** — 합성 영상은 배경이 균일해 오검출이 거의 없습니다. 실제로 무엇이 헛검출되는지는 0-B 이후

## 관련 문서

- [촬영 프로토콜 5.5](../../02-설계/CAPTURE-PROTOCOL.md) — 측정 정의와 판정 기준
- [DetectTrajectoriesRequest API](DetectTrajectories.md)
- [스포츠 영상 이벤트 라벨링](EventAnnotation.md)
- [레퍼런스 허브](../INDEX.md)

## 출처

- [Classification: Accuracy, recall, precision (Google ML Crash Course)](https://developers.google.com/machine-learning/crash-course/classification/accuracy-precision-recall)
- [Key Object Detection Metrics for Computer Vision](https://blog.roboflow.com/object-detection-metrics/)
- [Evaluating Object Detection Models: Methods and Metrics](https://www.geeksforgeeks.org/computer-vision/evaluating-object-detection-models-methods-and-metrics/)

---

[← 문서 허브](../../INDEX.md)
