---
title: "D-21 배포 / 인프라"
aliases: ["D-21", "배포 / 인프라"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-21
status: decided
group: "D. 백엔드"
depends_on: ["D-15", "D-20"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: 단일 VM + Docker Compose
---

# D-21. 배포 / 인프라

> **상태** ✅ **확정 — 단일 VM + Docker Compose** (2026-09-10) · **그룹** D. 백엔드

## 질문

백엔드를 어디에 어떻게 배포할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| 단일 VM + Docker Compose | 단순. 수동 운영 |
| Fly.io / Railway | 배포 간편. GPU 제약 |
| AWS ECS | 확장성. 복잡도 |
| Kubernetes | 과함 |

## 잠정안

**단일 VM + Docker Compose로 시작**

## 쟁점

- 초기에는 CPU 추론으로 시작하고, 필요할 때 워커만 GPU 인스턴스로 분리한다
- IaC(Terraform)는 Phase 3 이후에 검토한다
- D-20에서 GPU가 불필요하다고 판정되면 인프라가 크게 단순해진다

## 의존 관계

- **선행 결정**: [D-15](./D-15-baas-vs-selfhosted.md), [D-20](./D-20-server-ml.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

**단일 VM에 Docker Compose로 API · arq 워커 · PostgreSQL · Redis를 함께 올린다.**

## 근거

- [D-20](./D-20-server-ml.md)에서 서버 ML을 보류해 **GPU가 당장 필요 없다.** 일반 VM으로 충분하다
- Phase 2 사용자 규모가 작다. 오토스케일링·오케스트레이션이 필요한 시점이 아니다
- [D-18](./D-18-object-storage.md) R2가 영상 트래픽을 받아내므로 서버 대역폭 부담이 작다
- 비용과 구성 복잡도가 가장 낮다

## 구성

```
VM (Docker Compose)
├── api        FastAPI (uvicorn)
├── worker     arq
├── db         PostgreSQL 16
├── redis      Redis
└── caddy      리버스 프록시 + 자동 TLS
```

배포는 GHCR 이미지 빌드 → 태그 푸시 → VM에서 `docker compose pull && up -d`.

## 감수하는 것

**무중단 배포가 없다.** 재시작 시 수 초 다운타임이 발생한다. 분석 작업은 큐에 남아 있으므로 유실되지 않는다. 사용자 규모가 커지면 그때 blue-green을 구성한다.

**백업을 직접 책임진다.** `pg_dump`를 크론으로 돌려 R2에 저장한다. 복구 절차를 문서화하고 실제로 한 번 복구 테스트를 한다.

## 확장 경로

| 시점 | 조치 |
|---|---|
| [D-20](./D-20-server-ml.md)에서 GPU 필요 판정 | 워커만 GPU 인스턴스로 분리. [D-17](./D-17-task-queue.md) 큐 라우팅 재검토 |
| DB 운영 부담 증가 | Neon 등 관리형으로 이전 (PostgreSQL이라 이전 용이) |
| 트래픽 증가 | API 수평 확장 → 이 시점에 Terraform 도입 검토 |

---

[← 결정 현황](../DECISION-LOG.md)
