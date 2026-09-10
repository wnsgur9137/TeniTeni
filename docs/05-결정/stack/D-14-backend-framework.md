---
title: "D-14 백엔드 언어 / 프레임워크"
aliases: ["D-14", "백엔드 언어 / 프레임워크"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-14
status: decided
group: "D. 백엔드"
depends_on: []
affects: ["D-15", "D-16", "D-17", "D-18", "D-19", "D-20", "D-21", "D-11"]
decide_by: "Phase 2 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Python 3.12 + FastAPI
---

# D-14. 백엔드 언어 / 프레임워크

> **상태** ✅ **확정 — Python + FastAPI** (2026-09-10) · **그룹** D. 백엔드

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

**Python 3.12 + FastAPI.** API와 ML 워커를 같은 언어로 유지한다.

## 근거

- **ML 파이프라인은 Python 외 선택지가 사실상 없다.** 다른 언어를 고르면 API 서비스와 ML 서비스를 따로 유지해야 하고, 1인 개발에서 이 비용은 치명적이다
- FastAPI가 OpenAPI 스펙을 자동 생성한다 → [D-11](./D-11-networking.md)의 DTO 생성 절충안이 가능해진다
- Pydantic v2로 런타임 검증이 강제되어 정적 타입의 부재를 상당 부분 보완한다

Vapor는 iOS와 도메인 모델을 공유할 수 있어 매력적이었으나, ML 워커를 Python으로 따로 두어야 하므로 Spring·Node와 같은 이중 관리 문제를 그대로 안는다.

## 메트릭 계산식 이중화 문제

[ADR-0001](../adr/ADR-0001-hybrid-inference.md)의 하이브리드 구조상 메트릭 계산 로직이 **Swift(온디바이스)와 Python(서버) 양쪽에 존재**하게 된다.

→ 대응: [D-09](./D-09-serialization.md)의 Protobuf 스키마를 공유 기준으로 삼고, **같은 입력에 대해 양쪽 결과가 일치하는지 골든 테스트로 검증**한다. 고정 샘플 영상의 포즈 시계열을 픽스처로 두고 CI에서 양쪽을 비교한다.

---

[← 결정 현황](../DECISION-LOG.md)
