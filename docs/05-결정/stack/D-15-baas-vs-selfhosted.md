---
title: "D-15 자체 구축 vs BaaS"
aliases: ["D-15", "자체 구축 vs BaaS"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-15
status: open
group: "D. 백엔드"
depends_on: ["D-14"]
affects: ["D-16", "D-18", "D-19", "D-21"]
decide_by: "Phase 2 착수 직전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-15. 자체 구축 vs BaaS

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2 착수 직전

## 질문

API 레이어를 직접 만들 것인가, BaaS로 대체할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| FastAPI 자체 구축 | 비즈니스 로직 자유. 개발량 많음 |
| Supabase + Python 워커 | Auth/DB/Storage 무료 획득. Phase 2를 수 주 단축 |
| Firebase + 워커 | 모바일 친화적. Postgres 아님 |

## 잠정안

**미정 — **가장 중요한 백엔드 결정****

## 쟁점

- 서버에서 할 일이 '분석 워커 트리거 + 결과 조회'뿐이라면 Supabase로 충분하다
- 비즈니스 로직이 늘어나면 클라이언트와 DB 함수로 분산되어 유지가 어려워진다
- Supabase는 Postgres 기반이라 이관 경로가 열려 있다
- **결정 시점을 Phase 2 착수 직전으로 미뤄도 된다**

## 의존 관계

- **선행 결정**: [D-14](./D-14-backend-framework.md)
- **영향받는 결정**: [D-16](./D-16-database.md), [D-18](./D-18-object-storage.md), [D-19](./D-19-authentication.md), [D-21](./D-21-deployment.md)

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)
- [시스템 아키텍처](../../02-설계/ARCHITECTURE.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
