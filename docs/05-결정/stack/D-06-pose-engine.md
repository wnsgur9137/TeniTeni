---
title: "D-06 포즈 추정 엔진"
aliases: ["D-06", "포즈 추정 엔진"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-06
status: open
group: "B. 비전 파이프라인"
depends_on: []
affects: ["D-07", "D-09", "D-10"]
decide_by: "Phase 0"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-06. 포즈 추정 엔진

> **상태** ⬜ 미결 · **그룹** B. 비전 파이프라인 · **확정 시점** Phase 0

## 질문

실시간 포즈 추정을 어떤 엔진으로 할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Apple Vision | 19관절. 의존성 0, ANE 최적화, 무료 |
| MediaPipe Pose (BlazePose) | 33관절. 발끝 포함. 바이너리 크기 증가 |
| MoveNet Thunder | 17관절. 정확도 우위 없음 |
| YOLO-Pose | 다중 인물 강함. 단일 인물에 과함 |

## 잠정안

**Apple Vision**

## 쟁점

- Vision은 19관절이라 **발끝이 없다**. 체중 이동 분석에 발끝이 필요하면 MediaPipe 재검토
- **결정 근거 필요**: 메트릭 목록 중 발끝이 필수인 것이 실제로 있는가
- Vision을 쓰면 스켈레톤 본 정의와 메트릭 계산식이 19관절에 고정된다

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-07](./D-07-overlay-rendering.md), [D-09](./D-09-serialization.md), [D-10](./D-10-swing-classifier.md)

## 영향받는 문서

- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)
- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
