---
title: "D-16 데이터베이스"
aliases: ["D-16", "데이터베이스"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-16
status: decided
group: "D. 백엔드"
depends_on: ["D-15"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: PostgreSQL 16
---

# D-16. 데이터베이스

> **상태** ✅ **확정 — PostgreSQL 16** (2026-09-10) · **그룹** D. 백엔드

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

**PostgreSQL 16.** TimescaleDB 확장은 사용하지 않는다.

## 근거

- [D-09](./D-09-serialization.md)에서 포즈 시계열을 Protobuf 파일로 빼기로 해 **DB는 메타데이터만 다룬다.** TimescaleDB의 명분이 사라졌다
- SQLAlchemy 2.0 + Alembic 조합이 성숙하고 파이썬 생태계가 Postgres 중심이다
- 관리형 서비스 선택지가 넓다(Neon, Supabase, RDS) → [D-21](./D-21-deployment.md)에서 이전이 쉽다

## 저장 대상

| 테이블 | 내용 |
|---|---|
| users | Apple ID, 닉네임, 주손, 실력 수준 |
| sessions | 연습 세션 메타, 스윙 수, 평균 점수 |
| clips | 영상 메타, 스토리지 키, 업로드·분석 상태 |
| swings | 구간, 유형, 페이즈, 점수 |
| swing_metrics | 관절 각도 등 정량 지표 |
| feedbacks | 심각도, 대상 관절, 메시지 |
| reference_swings | 프로 레퍼런스 (Phase 3) |

포즈 시계열과 영상은 오브젝트 스토리지([D-18](./D-18-object-storage.md))에 두고 DB에는 키만 저장한다.

---

[← 결정 현황](../DECISION-LOG.md)
