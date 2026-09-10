---
title: "D-17 작업 큐"
aliases: ["D-17", "작업 큐"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-17
status: open
group: "D. 백엔드"
depends_on: ["D-14"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-17. 작업 큐

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

## 질문

비동기 분석 작업을 어떤 큐로 처리할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Celery + Redis | 기능 풍부. 무겁고 설정 복잡 |
| arq | async 네이티브. FastAPI와 궁합 좋음 |
| Dramatiq | 단순. 생태계 작음 |
| SQS 등 클라우드 큐 | 운영 부담 없음. 벤더 종속 |

## 잠정안

**Celery + Redis**

## 쟁점

- 영상 분석은 수십 초~분 단위라 동기 처리가 불가능하다
- arq가 FastAPI와 더 자연스럽고 설정이 훨씬 가볍다
- 재시도·데드레터·진행률 보고 요구사항을 먼저 정의해야 판단이 선다

## 의존 관계

- **선행 결정**: [D-14](./D-14-backend-framework.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
