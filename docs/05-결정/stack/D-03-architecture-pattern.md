---
title: "D-03 아키텍처 패턴"
aliases: ["D-03", "아키텍처 패턴"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-03
status: decided
group: "A. iOS 기반"
depends_on: ["D-02"]
affects: ["D-12"]
decide_by: "Phase 1 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Clean Architecture + TCA
---

# D-03. 아키텍처 패턴

> **상태** ✅ **확정 — Clean Architecture + TCA** (2026-09-10) · **그룹** A. iOS 기반

## 질문

어떤 아키텍처 패턴으로 화면 계층을 구성할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| **Clean Architecture + TCA** ✅ | 계층 분리는 Clean, Presentation은 TCA Store/Reducer |
| Clean Architecture + MVVM | 러닝커브 없음. 촬영 화면 ViewModel 비대화 위험 |
| MVI | 단방향 흐름을 직접 구현. 보일러플레이트 유지 부담 |

## 잠정안

**Clean Architecture + MVVM**

## 쟁점

**복잡도가 한 화면에 몰려 있다.** 촬영 화면 하나가 다음 상태를 동시에 들고 있다.

```
카메라 세션 상태     (설정 중 / 실행 / 인터럽션 / 오류)
분석 파이프라인 상태  (포즈 스트림, 궤적 스트림, 프레임 드롭률)
스윙 검출 상태       (대기 / 후보 감지 / 확정 / 클립 기록 중)
녹화 상태           (링 버퍼, AVAssetWriter 세션)
UI 상태             (오버레이, 가이드, 흔들림 경고, 발열 경고)
```

나머지 5~6개 화면은 평범하다.

**MVVM과 TCA는 같은 자리를 차지한다.** 병기할 수 없으며, Presentation 계층에서 하나를 골라야 한다. Clean Architecture는 계층 분리에 관한 것이므로 어느 쪽과도 결합 가능하다.

**TCA의 실질 비용**

- 러닝커브와 매크로로 인한 빌드 시간 증가
- **초당 60회 프레임 이벤트를 Reducer 액션으로 흘리면 성능과 디버깅이 무너진다.** 액션 로깅이 무용지물이 되고 디스패치 오버헤드가 프레임 예산을 잠식한다

**TCA로 해결되지 않는 것**

이 앱에서 진짜 어려운 것은 화면 상태 관리가 아니라 **비전 파이프라인**이다. 60fps 프레임 처리, 백프레셔, 발열 대응, 검출 정확도는 전부 `VisionKit` 안에서 벌어지며 아키텍처 패턴이 닿지 않는다.

## 의존 관계

- **선행 결정**: [D-02](./D-02-ui-framework.md)
- **영향받는 결정**: [D-12](./D-12-dependency-injection.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)

## 결정

**Clean Architecture(계층 분리) + TCA(Presentation 계층)** 로 간다.

- Domain: 순수 Swift. Entity, UseCase, Repository 프로토콜. 의존성 0
- Data: Repository 구현, 네트워크, 영속화
- Presentation: TCA Store / Reducer / View
- VisionKit: 분석 엔진. TCA와 무관한 독립 모듈

## 근거

TCA는 촬영 화면의 상태 얽힘을 Reducer 합성으로 분해하고, `TestStore`로 상태 전이를 강하게 테스트할 수 있다. 나머지 화면이 단순한 것은 TCA의 부담이 크지 않다는 뜻이기도 하다.

Domain 계층을 순수 Swift로 유지하는 것은 TCA와 무관하게 지킨다. Reducer가 UseCase를 호출하는 구조다.

## ⚠️ 필수 규칙: 프레임 스트림은 TCA 바깥

**이 규칙을 어기면 Phase 1에서 반드시 문제가 된다.**

```
VisionKit (TCA 바깥)
  프레임 → 포즈/궤적 → 스무딩 → 오버레이 상태
    ↓ AsyncStream, 60fps
  CaptureView의 오버레이 레이어가 직접 구독 (@Observable)

  ↓ 의미 있는 사건만 추려서 (초당 수 회 이하)
Store / Reducer
  .swingDetected(Swing)
  .sessionStateChanged(CameraState)
  .thermalWarning(ThermalState)
  .recordingFinished(Clip)
```

| 경로 | 빈도 | 처리 |
|---|---|---|
| 포즈/궤적 프레임 | 60fps | `AsyncStream` → `@Observable` 오버레이 상태. **Store 경유 금지** |
| 스윙 검출, 세션 상태, 발열, 녹화 완료 | 초당 수 회 이하 | Reducer 액션 |

## 함께 결정된 것

| 결정 | 영향 |
|---|---|
| [D-04](./D-04-concurrency.md) | Swift Concurrency + TCA Effect. 프레임 파이프라인은 `AsyncStream`으로 Store 바깥. RxSwift 확정 제외 |
| [D-12](./D-12-dependency-injection.md) | `swift-dependencies`가 TCA에 내장되어 사실상 결정됨 |
| [D-05](./D-05-module-tooling.md) | Tuist 확정 (함께 답변됨) |

---

[← 결정 현황](../DECISION-LOG.md)
