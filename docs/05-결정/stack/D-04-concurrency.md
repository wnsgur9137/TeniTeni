---
title: "D-04 비동기 / 상태 관리"
aliases: ["D-04", "비동기 / 상태 관리"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-04
status: open
group: "A. iOS 기반"
depends_on: ["D-02", "D-03"]
affects: []
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-04. 비동기 / 상태 관리

> **상태** ⬜ 미결 · **그룹** A. iOS 기반 · **확정 시점** Phase 0 이전

## 질문

프레임 파이프라인과 상태 전파를 무엇으로 구현할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Swift Concurrency 단독 | AsyncStream 기반. 백프레셔 제어 명시적 |
| Swift Concurrency + Combine | UI 바인딩만 Combine |
| RxSwift | 기존 프로젝트 컨벤션 |

## 잠정안

**Swift Concurrency 단독**

## 쟁점

- 비디오 프레임은 **백프레셔 제어가 핵심**이다. 분석이 밀리면 프레임을 버려야 한다
- Rx의 기본 동작은 버퍼링이라 프레임을 쌓다가 메모리가 터진다
- 의존성을 줄이면 Swift 6 strict concurrency 대응이 쉬워진다

## 의존 관계

- **선행 결정**: [D-02](./D-02-ui-framework.md), [D-03](./D-03-architecture-pattern.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
