---
title: "D-03 아키텍처 패턴"
aliases: ["D-03", "아키텍처 패턴"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-03
status: open
group: "A. iOS 기반"
depends_on: ["D-02"]
affects: ["D-12"]
decide_by: "Phase 1 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-03. 아키텍처 패턴

> **상태** ⬜ 미결 · **그룹** A. iOS 기반 · **확정 시점** Phase 1 이전

## 질문

어떤 아키텍처 패턴으로 화면 계층을 구성할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Clean Architecture + MVVM | 기존 경험과 일치. 러닝커브 없음 |
| TCA | 상태가 복잡한 촬영 화면에 유리. 러닝커브와 빌드 시간 비용 |
| MVI | 단방향 흐름. 생태계가 얕음 |

## 잠정안

**Clean Architecture + MVVM**

## 쟁점

- 화면 6~7개 규모에 TCA는 과할 수 있다
- 다만 촬영 화면은 카메라·분석·녹화·오버레이 상태가 얽혀 상태 관리 난이도가 높다
- Domain 계층을 순수 Swift로 두는 것은 어느 패턴이든 공통

## 의존 관계

- **선행 결정**: [D-02](./D-02-ui-framework.md)
- **영향받는 결정**: [D-12](./D-12-dependency-injection.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
