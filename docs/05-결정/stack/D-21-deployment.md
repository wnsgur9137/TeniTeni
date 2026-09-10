---
title: "D-21 배포 / 인프라"
aliases: ["D-21", "배포 / 인프라"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-21
status: open
group: "D. 백엔드"
depends_on: ["D-15", "D-20"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-21. 배포 / 인프라

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

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

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
