---
title: "D-12 의존성 주입"
aliases: ["D-12", "의존성 주입"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-12
status: decided
group: "C. iOS 부가 스택"
depends_on: ["D-03"]
affects: []
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: swift-dependencies (TCA 내장)
---

# D-12. 의존성 주입

> **상태** ✅ **확정 — swift-dependencies** (2026-09-10) · **그룹** C. iOS 부가 스택

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

**swift-dependencies** (TCA 내장). Repository·VisionKit·시스템 서비스를 모두 `DependencyValues`에 등록한다.

## 근거

- [D-03](./D-03-architecture-pattern.md) TCA 채택으로 **이미 포함된 라이브러리**다. 추가 의존성이 0
- `TestStore`와 통합되어 있어 `withDependencies`로 테스트 격리가 깔끔하다
- 다른 DI를 얹으면 Reducer는 `@Dependency`, 그 외는 다른 방식이 되어 **주입 경로가 두 개로 갈라진다**

## 등록 대상

| 종류 | 예 |
|---|---|
| Repository | `clipRepository`, `swingRepository`, `sessionRepository` |
| VisionKit | `poseEstimator`, `ballTracker`, `swingClassifier` |
| 시스템 | `cameraSession`, `clipRecorder`, `thermalMonitor`, `motionMonitor` |
| 인프라 | `apiClient`(Moya), `fileStore`, `uploadService` |

`Projects/App/Sources/DI/DependencyValues+App.swift`에서 live 값을, 각 모듈 테스트에서 test 값을 주입한다.

---

[← 결정 현황](../DECISION-LOG.md)
