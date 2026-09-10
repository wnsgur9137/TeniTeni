---
title: "D-16 데이터베이스"
aliases: ["D-16", "데이터베이스"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-16
status: open
group: "D. 백엔드"
depends_on: ["D-15"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-16. 데이터베이스

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

## 질문

서버 데이터베이스를 무엇으로 할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| PostgreSQL 16 | 표준. 확장 풍부 |
| PostgreSQL + TimescaleDB | 시계열 집계 최적화 |
| MySQL | 익숙함. 확장성 열위 |

## 잠정안

**PostgreSQL 16**

## 쟁점

- 프레임 시계열을 DB에 넣을지에 따라 TimescaleDB 필요 여부가 갈린다
- 현 설계는 시계열을 파일로 빼므로 일반 Postgres로 충분할 가능성이 높다

## 의존 관계

- **선행 결정**: [D-15](./D-15-baas-vs-selfhosted.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
