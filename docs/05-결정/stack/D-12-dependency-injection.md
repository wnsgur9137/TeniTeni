---
title: "D-12 의존성 주입"
aliases: ["D-12", "의존성 주입"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-12
status: open
group: "C. iOS 부가 스택"
depends_on: ["D-03"]
affects: []
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-12. 의존성 주입

> **상태** ⬜ 미결 · **그룹** C. iOS 부가 스택 · **확정 시점** Phase 1

## 질문

의존성 주입을 어떻게 구성할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| 수동 Composition Root | 의존성 0. 명시적 |
| Factory | 경량. 프로퍼티 래퍼 기반 |
| swift-dependencies | TCA 생태계. 테스트 지원 강함 |
| Swinject | 런타임 컨테이너. 컴파일 타임 안전성 없음 |

## 잠정안

**수동 Composition Root**

## 쟁점

- 모듈이 10개 내외면 수동 구성으로 충분하다
- TCA를 택하면 swift-dependencies가 자연스러운 짝이 된다

## 의존 관계

- **선행 결정**: [D-03](./D-03-architecture-pattern.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
