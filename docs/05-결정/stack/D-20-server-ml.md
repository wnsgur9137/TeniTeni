---
title: "D-20 서버 ML 스택"
aliases: ["D-20", "서버 ML 스택"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-20
status: open
group: "D. 백엔드"
depends_on: ["D-10"]
affects: ["D-21"]
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-20. 서버 ML 스택

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

## 질문

서버 정밀 분석에 어떤 모델을 쓸 것인가? 애초에 필요한가?

## 후보

| 후보 | 메모 |
|---|---|
| TrackNetV2/V3 | 공 추적. 테니스 논문 표준 |
| MMPose (ViTPose/HRNet) | 고정밀 포즈 |
| MotionBERT 계열 | 2D→3D 리프팅 |
| 도입하지 않음 | 온디바이스로 충분하다면 |

## 잠정안

**미정**

## 쟁점

- **선결 조건: 서버 정밀 분석이 온디바이스 대비 유의미한 개선을 주는지 정량 검증**
- 차이가 작으면 서버 ML 자체를 축소하거나 제거한다. GPU 비용 대비 가치가 없다
- 이 결정이 GPU 필요 여부 → 인프라 비용을 결정한다

## 의존 관계

- **선행 결정**: [D-10](./D-10-swing-classifier.md)
- **영향받는 결정**: [D-21](./D-21-deployment.md)

## 영향받는 문서

- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)
- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
