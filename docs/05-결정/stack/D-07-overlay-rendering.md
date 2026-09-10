---
title: "D-07 오버레이 렌더링"
aliases: ["D-07", "오버레이 렌더링"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-07
status: open
group: "B. 비전 파이프라인"
depends_on: ["D-02", "D-06"]
affects: []
decide_by: "Phase 0"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-07. 오버레이 렌더링

> **상태** ⬜ 미결 · **그룹** B. 비전 파이프라인 · **확정 시점** Phase 0

## 질문

스켈레톤·궤적 오버레이를 무엇으로 그릴 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| SwiftUI Canvas | 관절 19개엔 충분. 구현 빠름 |
| CAShapeLayer | 무난. 매 프레임 path 재생성 비용 |
| Metal | 프리뷰 직접 렌더 → 지연 0. 구현 비용 큼 |

## 잠정안

**SwiftUI Canvas → Phase 1에 Metal 전환**

## 쟁점

- 핵심은 **지연 문제**다. 프리뷰 레이어 위에 오버레이하면 스켈레톤이 1~3프레임 늦는다
- 테니스 스윙 속도에서는 팔이 스켈레톤 밖으로 튀어나간다
- Metal로 프리뷰를 직접 렌더해야 지연이 0이 된다
- 중간 단계로 속도 외삽(extrapolation)을 쓸 수 있다

## 의존 관계

- **선행 결정**: [D-02](./D-02-ui-framework.md), [D-06](./D-06-pose-engine.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
