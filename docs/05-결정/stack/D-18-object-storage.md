---
title: "D-18 오브젝트 스토리지"
aliases: ["D-18", "오브젝트 스토리지"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-18
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

# D-18. 오브젝트 스토리지

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

## 질문

영상 파일을 어디에 저장할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Cloudflare R2 | **egress 무료**. 영상 서비스에 결정적 |
| AWS S3 | 생태계 최강. egress 비쌈 |
| Supabase Storage | BaaS 채택 시 통합 편의 |

## 잠정안

**Cloudflare R2**

## 쟁점

- 영상 다운로드가 반복되므로 egress 비용 차이가 크게 벌어진다
- presigned URL로 앱이 직접 업로드해 API 서버를 우회한다

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
