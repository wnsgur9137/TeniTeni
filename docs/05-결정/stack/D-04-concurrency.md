---
title: "D-04 비동기 / 상태 관리"
aliases: ["D-04", "비동기 / 상태 관리"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-04
status: decided
group: "A. iOS 기반"
depends_on: ["D-02", "D-03"]
affects: []
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Swift Concurrency + AsyncStream (오버레이/분석 스트림 분리)
---

# D-04. 비동기 / 상태 관리

> **상태** ✅ **확정 — Swift Concurrency, 스트림 분리** (2026-09-10) · **그룹** A. iOS 기반

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

**Swift Concurrency 단독.** RxSwift·Combine 미도입.

| 영역 | 구현 |
|---|---|
| 프레임 파이프라인 | `AsyncStream` (TCA 바깥, [D-03](./D-03-architecture-pattern.md) 규칙) |
| Reducer 사이드이펙트 | TCA `Effect` |
| 백프레셔 | **오버레이/분석 스트림 분리** |

### 백프레셔 — 스트림 분리

궤적 검출과 오버레이는 요구가 정반대다. 궤적(`DetectTrajectoriesRequest`)은 **연속 프레임**에서 포물선을 찾으므로 프레임을 건너뛰면 검출률이 떨어지고, 오버레이는 **최신 프레임**이어야 몸을 따라간다.

```
CMSampleBuffer
  ├─→ 오버레이 스트림   AsyncStream(.bufferingNewest(1))  최신성 우선
  └─→ 분석 스트림       직렬 큐, 프레임 누락 없이 처리     연속성 우선
                        (해상도를 더 낮춰 예산 확보)
```

`.unbounded`는 메모리가 폭발하므로 어떤 경우에도 사용하지 않는다.

## 근거

- Rx의 기본 동작은 버퍼링이라 분석이 밀릴 때 프레임이 쌓여 메모리가 터진다. 60fps 파이프라인에서 백프레셔를 명시적으로 제어하려면 `AsyncStream`이 맞다
- 의존성을 줄이면 Swift 6 strict concurrency 대응이 쉬워진다. 신규 Vision API가 `Sendable`이라 궁합도 좋다
- 단일 스트림은 어느 정책을 쓰든 한쪽을 희생한다. **Phase 0 게이트가 궤적 검출률 70%** 이므로 검출률을 희생하는 선택은 위험하다

⬜ **Phase 0에서 실측 후 확정할 수치**: 분석 스트림 해상도, 오버레이 버퍼 크기, `frameAnalysisSpacing`

---

[← 결정 현황](../DECISION-LOG.md)
