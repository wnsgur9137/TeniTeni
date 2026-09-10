---
title: "D-10 스윙 분류 모델"
aliases: ["D-10", "스윙 분류 모델"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-10
status: open
group: "B. 비전 파이프라인"
depends_on: ["D-06"]
affects: ["D-20"]
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-10. 스윙 분류 모델

> **상태** ⬜ 미결 · **그룹** B. 비전 파이프라인 · **확정 시점** Phase 1

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

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
