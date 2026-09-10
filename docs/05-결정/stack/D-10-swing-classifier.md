---
title: "D-10 스윙 분류 모델"
aliases: ["D-10", "스윙 분류 모델"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-10
status: decided
group: "B. 비전 파이프라인"
depends_on: ["D-06"]
affects: ["D-20"]
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Create ML Action Classifier
---

# D-10. 스윙 분류 모델

> **상태** ✅ **확정 — Create ML Action Classifier** (2026-09-10) · **그룹** B. 비전 파이프라인

## 질문

스윙 유형(포핸드/백핸드/서브/발리)을 어떤 모델로 분류할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Create ML Action Classifier | Apple 공식 경로. 툴체인 안정적 |
| 커스텀 1D-CNN | 유연. 초기 비용 큼 |
| GRU / LSTM | 시퀀스에 자연스러움 |
| 소형 Transformer | 성능 상한 높음. 데이터 요구량 큼 |

## 잠정안

**Create ML Action Classifier**

## 쟁점

- Create ML은 툴체인이 안정적이지만 커스터마이즈가 제한적이다
- **선결 조건: 학습 데이터 확보 계획.** 유형별 200회 이상 자체 촬영이 필요하다
- 커스텀 모델은 서버에서 PyTorch로 학습 후 Core ML 변환 경로가 필요하다

## 의존 관계

- **선행 결정**: [D-06](./D-06-pose-engine.md)
- **영향받는 결정**: [D-20](./D-20-server-ml.md)

## 영향받는 문서

- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)

## 결정

**Create ML Action Classifier** (`MLActionClassifier`). 4종 분류 — forehand / backhand / serve / volley (+ none).

## 근거

- [D-06](./D-06-pose-engine.md) Vision의 `HumanBodyPoseObservation.keypoints`가 **Core ML 호환 multi-array**로 나온다. 변환 레이어가 거의 없다
- Apple 공식 경로라 툴체인이 안정적이고 Mac에서 바로 학습해 Core ML로 떨어진다
- **학습 데이터가 적은 초기에는 단순한 모델이 유리하다.** 커스텀 모델의 성능 상한은 데이터가 충분할 때만 의미가 있다

## 진짜 병목은 데이터다

모델 선택보다 **학습 데이터 확보가 어렵다.** 유형별 200회 이상이 필요하다.

1. 자체 촬영 (본인 + 지인) — 유형별 200회+
2. 증강 — 좌우 반전, 시간 신축, 관절 노이즈 주입
3. 공개 데이터셋 검토 — THETIS, Tenniset 등
4. 출시 후 사용자 데이터 수집(옵트인) → 재학습

## 교체 경로

정확도 90% 목표에 미달하거나 페이즈 분할이 부정확하면 커스텀 1D-CNN / GRU로 옮긴다. **수집한 데이터는 그대로 재사용**되므로 전환 비용은 학습 파이프라인 구축에 한정된다. 이 경우 `server/ml/`의 PyTorch 학습 → `coremltools` 변환 경로를 사용한다.

---

[← 결정 현황](../DECISION-LOG.md)
