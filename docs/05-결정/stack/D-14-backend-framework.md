---
title: "D-14 백엔드 언어 / 프레임워크"
aliases: ["D-14", "백엔드 언어 / 프레임워크"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-14
status: open
group: "D. 백엔드"
depends_on: []
affects: ["D-15", "D-16", "D-17", "D-18", "D-19", "D-20", "D-21", "D-11"]
decide_by: "Phase 2 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-14. 백엔드 언어 / 프레임워크

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2 이전

## 질문

백엔드를 어떤 언어와 프레임워크로 구현할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Python + FastAPI | ML과 언어 통일. OpenAPI 자동 생성 |
| Swift + Vapor | iOS와 도메인 모델 공유 가능. ML 생태계 없음 |
| Kotlin + Spring | 타입 안정성. ML과 언어 분리 |
| Node + NestJS | 개발 속도. ML 라이브러리 부재 |
| Go | 성능·배포 단순. 동일한 ML 분리 문제 |

## 잠정안

**Python + FastAPI**

## 쟁점

- ML 파이프라인은 Python이 사실상 강제다. API를 다른 언어로 쓰면 **서비스를 두 개 유지**해야 한다
- **단 Vapor는 iOS와 도메인 모델을 공유할 수 있어 별도 검토 가치가 있다**
- 1인 개발에서 언어 이중화 비용은 치명적이다

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-15](./D-15-baas-vs-selfhosted.md), [D-16](./D-16-database.md), [D-17](./D-17-task-queue.md), [D-18](./D-18-object-storage.md), [D-19](./D-19-authentication.md), [D-20](./D-20-server-ml.md), [D-21](./D-21-deployment.md), [D-11](./D-11-networking.md)

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
