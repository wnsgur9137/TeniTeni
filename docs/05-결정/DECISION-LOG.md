---
title: "결정 현황"
aliases: ["결정 현황", "Decision Log", "스택 결정"]
tags:
  - 문서유형/MOC
  - 영역/프로세스
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 결정 현황

설계 문서의 모든 🟡 잠정 / ⬜ 미결 항목을 하나씩 확정하기 위한 허브입니다.

**진행: 4 / 22 확정**

## 진행 방법

1. 아래 순서대로 한 항목씩 다룹니다. **순서는 의존 관계를 따릅니다** — 앞 항목이 뒤 항목의 선택지를 좁힙니다
2. 각 결정 노트에서 후보·쟁점을 검토하고 결론과 근거를 노트에 기록합니다
3. 확정되면 노트의 프론트매터 `status`를 `decided`로 바꾸고 `decided_on`·`decision`을 채웁니다
4. 영향받는 설계 문서의 상태 표기(🟡 → ✅)도 함께 갱신합니다
5. 되돌리기 어려운 결정은 [adr](./adr/)에 ADR을 추가합니다

## A. iOS 기반 — 다른 모든 것에 영향

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-01](./stack/D-01-deployment-target.md) | 최소 iOS 타깃 버전 | **iOS 26.0** | 2026-09-10 | ✅ |
| [D-02](./stack/D-02-ui-framework.md) | UI 프레임워크 | **전면 SwiftUI** | 2026-09-10 | ✅ |
| [D-03](./stack/D-03-architecture-pattern.md) | 아키텍처 패턴 | **Clean + TCA** | 2026-09-10 | ✅ |
| [D-04](./stack/D-04-concurrency.md) | 비동기 / 상태 관리 | Swift Concurrency + TCA Effect | Phase 0 이전 | ⬜ (D-03이 좁힘) |
| [D-05](./stack/D-05-module-tooling.md) | 모듈 빌드 도구 | **Tuist 4** | 2026-09-10 | ✅ |

## B. 비전 파이프라인

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-06](./stack/D-06-pose-engine.md) | 포즈 추정 엔진 | Apple Vision | Phase 0 | ⬜ |
| [D-07](./stack/D-07-overlay-rendering.md) | 오버레이 렌더링 | Canvas → Metal | Phase 0 | ⬜ |
| [D-08](./stack/D-08-local-db.md) | 로컬 데이터베이스 | SwiftData | Phase 1 | ⬜ |
| [D-09](./stack/D-09-serialization.md) | 포즈 시계열 직렬화 | Protobuf | Phase 1 | ⬜ |
| [D-10](./stack/D-10-swing-classifier.md) | 스윙 분류 모델 | Create ML | Phase 1 | ⬜ |

## C. iOS 부가 스택

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-11](./stack/D-11-networking.md) | 네트워크 계층 | openapi-generator | Phase 2 | ⬜ |
| [D-12](./stack/D-12-dependency-injection.md) | 의존성 주입 | swift-dependencies | Phase 1 | ⬜ (D-03이 좁힘) |
| [D-13](./stack/D-13-observability.md) | 크래시 리포팅 / 분석 | 미정 | Phase 1 | ⬜ |

## D. 백엔드 — Phase 2 직전까지 미뤄도 무방

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-14](./stack/D-14-backend-framework.md) | 백엔드 언어 / 프레임워크 | Python + FastAPI | Phase 2 이전 | ⬜ |
| [D-15](./stack/D-15-baas-vs-selfhosted.md) | **자체 구축 vs BaaS** | 미정 | Phase 2 직전 | ⬜ |
| [D-16](./stack/D-16-database.md) | 데이터베이스 | PostgreSQL 16 | Phase 2 | ⬜ |
| [D-17](./stack/D-17-task-queue.md) | 작업 큐 | Celery + Redis | Phase 2 | ⬜ |
| [D-18](./stack/D-18-object-storage.md) | 오브젝트 스토리지 | Cloudflare R2 | Phase 2 | ⬜ |
| [D-19](./stack/D-19-authentication.md) | 인증 | 미정 | Phase 2 | ⬜ |
| [D-20](./stack/D-20-server-ml.md) | 서버 ML 스택 | 미정 | Phase 2 | ⬜ |
| [D-21](./stack/D-21-deployment.md) | 배포 / 인프라 | 단일 VM + Compose | Phase 2 | ⬜ |

## E. 저장소 / 프로세스

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-22](./stack/D-22-repository-workflow.md) | 저장소 구조 및 워크플로 | 모노레포 + trunk-based | 첫 커밋 전 | ⬜ |

## 결정 순서

```
D-01 (타깃) → D-02 (UI) → D-03 (아키텍처) → D-04 (비동기) → D-05 (모듈)
     ↓
D-06 (포즈 엔진) → D-07 (렌더링) → D-08 (DB) → D-09 (직렬화) → D-10 (분류 모델)
     ↓
D-11 ~ D-13 (부가 스택)
     ↓
D-22 (저장소) ← Phase 0 시작 가능 지점
     ↓  ... Phase 0 기술 검증 후 ...
D-14 ~ D-21 (백엔드) ← Phase 2 착수 직전에 확정해도 늦지 않음
```

> **백엔드 결정(D-14~D-21)은 서두르지 않아도 됩니다.**
> [ADR-0001](./adr/ADR-0001-hybrid-inference.md)의 오프라인 우선 원칙에 따라 Phase 0/1은 백엔드 없이 진행되며,
> Phase 0의 기술 검증 결과가 백엔드 요구사항 자체를 바꿀 수 있습니다.

## 결정 기록 (ADR)

되돌리기 어렵거나 근거를 남길 가치가 있는 결정만 ADR로 기록합니다.

| # | 제목 | 상태 |
|---|---|---|
| [ADR-0001](./adr/ADR-0001-hybrid-inference.md) | 온디바이스/서버 하이브리드 추론 구조 | Accepted |
| [ADR-0002](./adr/ADR-0002-monorepo.md) | 모노레포 채택 | Proposed |
| [ADR-0003](./adr/ADR-0003-rule-based-evaluation.md) | 자세 평가는 룰 엔진 우선 | Accepted |

ADR 상태: **Proposed**(제안) / **Accepted**(채택) / **Superseded by ADR-XXXX** / **Deprecated**

---

[← 문서 허브](../INDEX.md)
