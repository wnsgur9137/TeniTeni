---
title: "D-08 로컬 데이터베이스"
aliases: ["D-08", "로컬 데이터베이스"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-08
status: open
group: "B. 비전 파이프라인"
depends_on: ["D-01"]
affects: ["D-09"]
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-08. 로컬 데이터베이스

> **상태** ⬜ 미결 · **그룹** B. 비전 파이프라인 · **확정 시점** Phase 1

## 질문

메타데이터를 어떤 로컬 DB에 저장할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| SwiftData | iOS 17+. SwiftUI 통합 자연스러움 |
| GRDB | 성숙. SQL 직접 제어 |
| Core Data | 검증됨. 보일러플레이트 많음 |
| Realm | 간편. 벤더 리스크 |

## 잠정안

**SwiftData**

## 쟁점

- SwiftData는 복잡한 쿼리·마이그레이션에서 아직 거친 부분이 있다
- GRDB는 성숙하고 SQL을 직접 제어할 수 있어 시계열 집계에 유리하다
- 포즈 시계열은 DB가 아니라 파일에 저장하므로 DB 부하 자체는 크지 않다

## 의존 관계

- **선행 결정**: [D-01](./D-01-deployment-target.md)
- **영향받는 결정**: [D-09](./D-09-serialization.md)

## 영향받는 문서

- [시스템 아키텍처](../../02-설계/ARCHITECTURE.md)
- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
