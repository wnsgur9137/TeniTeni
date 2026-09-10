---
title: "D-17 작업 큐"
aliases: ["D-17", "작업 큐"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-17
status: decided
group: "D. 백엔드"
depends_on: ["D-14"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: arq + Redis
---

# D-17. 작업 큐

> **상태** ✅ **확정 — arq + Redis** (2026-09-10) · **그룹** D. 백엔드

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

**arq + Redis.**

## 근거

- **async 네이티브**라 [D-14](./D-14-backend-framework.md) FastAPI와 같은 비동기 모델을 쓴다. Celery는 async 지원이 어색해 이질감이 생긴다
- 작업이 `analyze_clip`, `generate_report` **두 개뿐**이다. Celery 기능의 대부분을 쓰지 않는다
- 설정이 가볍고 Redis만 있으면 동작한다 → [D-21](./D-21-deployment.md) 단일 VM 구성에 적합

## 주의할 점

**모니터링 UI가 없다.** Celery의 Flower 같은 도구가 없으므로 작업 상태를 직접 노출해야 한다.

→ 대응: `clips.analysis_state`를 DB에서 관리하고([02. 시스템 아키텍처](../../02-설계/ARCHITECTURE.md) 2.5절 상태 머신), `GET /v1/clips/{id}` 로 진행 상태를 조회한다. 실패 시 `analysis_error`에 원인을 남긴다.

**GPU 워커 분리 시 재검토.** [D-20](./D-20-server-ml.md)에서 GPU가 필요하다고 판정되면 워커를 별도 인스턴스로 분리하는데, arq의 큐 라우팅 기능이 Celery보다 약하다. 그 시점에 큐를 나누는 방식(작업별 Redis 키 분리)으로 대응하거나 Celery 이전을 검토한다.

---

[← 결정 현황](../DECISION-LOG.md)
