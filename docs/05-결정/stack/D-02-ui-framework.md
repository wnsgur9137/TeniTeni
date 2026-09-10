---
title: "D-02 UI 프레임워크"
aliases: [ "D-02", "UI 프레임워크" ]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-02
status: decided
group: "A. iOS 기반"
depends_on: [ "D-01" ]
affects: [ "D-03", "D-04", "D-07" ]
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: 전면 SwiftUI (카메라 프리뷰만 UIViewRepresentable)
---

# D-02. UI 프레임워크

> **상태** ✅ **확정 — 전면 SwiftUI** (2026-09-10) · **그룹** A. iOS 기반

## 질문

SwiftUI와 UIKit 중 무엇을 주 프레임워크로 쓸 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| **전면 SwiftUI** ✅ | 카메라 프리뷰만 `UIViewRepresentable`로 래핑 |
| 하이브리드 | 촬영 화면만 UIKit. 두 세계를 오가는 비용 발생 |
| 전면 UIKit + SnapKit | 기존 컨벤션 유지. 오버레이·차트를 수동 구현해야 함 |

## 잠정안

**전면 SwiftUI**

## 쟁점

**기존 프로젝트와의 단절.** `noteing-ios`, `Timespread_IOS` 등에서 UIKit + RxSwift + SnapKit을 써 왔다. 신규에서 이를 버리려면 그만한 이유가 필요하다.

**SwiftUI를 택할 근거**

| 근거 | 내용 |
|---|---|
| 오버레이 렌더링 | `Canvas`가 스켈레톤·궤적 그리기에 그대로 맞는다. UIKit이면 `CAShapeLayer` 수동 관리 |
| 진척도 화면 | Swift Charts를 바로 쓴다. UIKit이면 차트 라이브러리 추가 필요 |
| 화면 수 | 6~7개. 복잡한 커스텀 트랜지션이 없다 |
| `@Observable` | [D-01](./D-01-deployment-target.md)에서 iOS 26 확정. 제약 없이 사용 가능하고 ViewModel 보일러플레이트가 크게 준다 |

**반대 근거와 그 반박**

촬영 화면은 이 앱에서 가장 명령형이다 — `AVCaptureSession` 생명주기, 포맷 전환, 방향 변경, 인터럽션(전화 수신) 처리, 링 버퍼. 선언형 모델과 잘 맞지 않는다.

다만 이 영역은 **어느 쪽을 택하든 `UIViewRepresentable` 안에 갇힌다.** [D-07](./D-07-overlay-rendering.md)에서 지연 문제로 Metal 프리뷰로 가면 `MTKView`를 래핑하게 되는데, 그 경계는 SwiftUI든 UIKit이든 동일하다. 즉 이 반대 근거는 실제로 결정을 가르지 못한다.

## 의존 관계

- **선행 결정**: [D-01](./D-01-deployment-target.md)
- **영향받는 결정**: [D-03](./D-03-architecture-pattern.md), [D-04](./D-04-concurrency.md), [D-07](./D-07-overlay-rendering.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

**전면 SwiftUI로 간다.** 카메라 프리뷰만 `UIViewRepresentable`로 래핑한다.

## 근거

- 명령형 영역(카메라)은 어느 쪽을 택해도 래핑 경계 안에 갇히므로, UIKit을 택해서 얻는 이점이 실질적으로 없다
- 반면 오버레이(`Canvas`)와 진척도(Swift Charts)는 SwiftUI에서만 공짜로 얻는다 — 이 앱의 핵심 화면 두 개다
- iOS 26 타깃이라 `@Observable`을 제약 없이 쓴다

### 경계 규칙

| 영역 | 구현 |
|---|---|
| 카메라 프리뷰 | `UIViewRepresentable` → `AVCaptureVideoPreviewLayer` (D-07에서 `MTKView`로 전환 가능) |
| 스켈레톤·궤적 오버레이 | SwiftUI `Canvas` |
| 그 외 전 화면 | SwiftUI |
| 상태 | `@Observable` |

**RxSwift는 도입하지 않는다.** UI 프레임워크와 무관한 별개 사안이며 [D-04](./D-04-concurrency.md)에서 다룬다. 비디오 프레임 파이프라인은 분석이 밀릴 때 프레임을 버려야 하는데(백프레셔), Rx의 기본 동작은 버퍼링이라 메모리가 터진다.

---

[← 결정 현황](../DECISION-LOG.md)
