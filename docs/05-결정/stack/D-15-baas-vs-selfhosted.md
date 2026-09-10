---
title: "D-15 자체 구축 vs BaaS"
aliases: ["D-15", "자체 구축 vs BaaS"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-15
status: decided
group: "D. 백엔드"
depends_on: ["D-14"]
affects: ["D-16", "D-18", "D-19", "D-21"]
decide_by: "Phase 2 착수 직전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: FastAPI 자체 구축
---

# D-15. 자체 구축 vs BaaS

> **상태** ✅ **확정 — FastAPI 자체 구축** (2026-09-10) · **그룹** D. 백엔드

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

**FastAPI로 자체 구축한다.** BaaS를 사용하지 않는다.

## 근거

- [D-14](./D-14-backend-framework.md)와 일관되게 API·워커를 한 코드베이스에서 관리한다
- 진척도 집계, 레퍼런스 DTW 비교 등 **서버 로직이 Phase 3에서 늘어난다.** BaaS였다면 이 시점에 클라이언트와 DB 함수로 로직이 흩어진다
- 벤더 종속이 없어 인프라 선택([D-21](./D-21-deployment.md))이 자유롭다

## 비용

인증·스토리지·권한을 직접 구현해야 해 **Phase 2가 길어진다.** 이를 줄이기 위해:

- 인증은 Sign in with Apple만 지원해 범위를 좁힌다 ([D-19](./D-19-authentication.md))
- 스토리지는 presigned URL로 위임해 파일 트래픽이 API 서버를 거치지 않게 한다 ([D-18](./D-18-object-storage.md))
- 권한 모델을 단순하게 유지한다 — 사용자는 자기 데이터만 접근. 공유 기능은 v1 범위 밖

---

[← 결정 현황](../DECISION-LOG.md)
