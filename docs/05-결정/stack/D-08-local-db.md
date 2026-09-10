---
title: "D-08 로컬 데이터베이스"
aliases: ["D-08", "로컬 데이터베이스"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-08
status: decided
group: "B. 비전 파이프라인"
depends_on: ["D-01"]
affects: ["D-09"]
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: SwiftData
---

# D-08. 로컬 데이터베이스

> **상태** ✅ **확정 — SwiftData** (2026-09-10) · **그룹** B. 비전 파이프라인

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

**SwiftData.** 메타데이터(User, Session, Clip, Swing, Metrics, Feedback)만 저장한다.

## 근거

- [D-01](./D-01-deployment-target.md) iOS 26 확정으로 제약 없이 사용 가능
- [D-02](./D-02-ui-framework.md) SwiftUI + `@Observable`과 바로 맞물려 보일러플레이트가 최소
- **포즈 시계열을 파일로 빼므로 DB 부하가 낮다** ([D-09](./D-09-serialization.md)). SwiftData의 약점(복잡한 쿼리·대용량)이 드러나기 어려운 구조

## 리스크와 대응

진척도 화면의 기간별 집계에서 SwiftData의 쿼리 표현력이 부족할 수 있다. 이 경우 **집계 결과를 별도 스냅샷 테이블에 미리 계산해 저장**하는 방식으로 우회한다. 그래도 부족하면 Phase 3에서 GRDB 이전을 검토하되, Repository 프로토콜 뒤에 가려져 있으므로 교체 비용은 Data 계층에 한정된다.

---

[← 결정 현황](../DECISION-LOG.md)
