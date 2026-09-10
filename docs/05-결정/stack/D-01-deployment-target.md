---
title: "D-01 최소 iOS 타깃 버전"
aliases: ["D-01", "최소 iOS 타깃 버전"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-01
status: open
group: "A. iOS 기반"
depends_on: []
affects: ["D-02", "D-03", "D-08"]
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-01. 최소 iOS 타깃 버전

> **상태** ⬜ 미결 · **그룹** A. iOS 기반 · **확정 시점** Phase 0 이전

## 질문

최소 지원 iOS 버전을 몇으로 할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| iOS 17.0 | 3D 포즈·@Observable·SwiftData·videoRotationAngle 사용 가능 |
| iOS 16.0 | 커버리지 넓음. 3D 포즈 포기 |
| iOS 18.0 | 최신 API 전부. 커버리지 손실 큼 |

## 잠정안

**iOS 17.0**

## 쟁점

- **선결 질문: 3D 포즈를 v1 범위에 넣을 것인가?** 이 답이 타깃을 결정한다
- 신규 앱이고 최신 기기 성능을 요구하므로 커버리지 손실의 실질 영향은 작다
- 17.0이면 `@Observable`·SwiftData·`RotationCoordinator`까지 함께 얻는다

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-02](./D-02-ui-framework.md), [D-03](./D-03-architecture-pattern.md), [D-08](./D-08-local-db.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
