---
title: "D-02 UI 프레임워크"
aliases: ["D-02", "UI 프레임워크"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-02
status: open
group: "A. iOS 기반"
depends_on: ["D-01"]
affects: ["D-03", "D-04", "D-07"]
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-02. UI 프레임워크

> **상태** ⬜ 미결 · **그룹** A. iOS 기반 · **확정 시점** Phase 0 이전

## 질문

SwiftUI와 UIKit 중 무엇을 주 프레임워크로 쓸 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| 전면 SwiftUI | 카메라 프리뷰만 UIViewRepresentable로 래핑 |
| 전면 UIKit + SnapKit | 기존 프로젝트 컨벤션과 일치 |
| 하이브리드 | 카메라 화면만 UIKit, 나머지 SwiftUI |

## 잠정안

**전면 SwiftUI**

## 쟁점

- 기존 프로젝트는 UIKit + RxSwift + SnapKit 조합. 신규에서 유지할 이유가 있는가
- 오버레이 렌더링에 `Canvas`가 적합하고, 진척도 화면에 Swift Charts를 바로 쓸 수 있다
- 화면 수가 6~7개로 적고 복잡한 커스텀 트랜지션이 없다

## 의존 관계

- **선행 결정**: [D-01](./D-01-deployment-target.md)
- **영향받는 결정**: [D-03](./D-03-architecture-pattern.md), [D-04](./D-04-concurrency.md), [D-07](./D-07-overlay-rendering.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
