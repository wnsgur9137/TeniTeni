---
title: "D-01 최소 iOS 타깃 버전"
aliases: [ "D-01", "최소 iOS 타깃 버전" ]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-01
status: decided
group: "A. iOS 기반"
depends_on: []
affects: [ "D-02", "D-03", "D-08" ]
decide_by: "Phase 0 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: iOS 26.0
---

# D-01. 최소 iOS 타깃 버전

> **상태** ✅ **확정 — iOS 26.0** (2026-09-10) · **그룹** A. iOS 기반

## 질문

최소 지원 iOS 버전을 몇으로 할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| **iOS 26.0** ✅ | 최신 Vision·SwiftUI·Core ML API를 제약 없이 사용. 레거시 분기 없음 |
| iOS 18.0 | 신규 Swift Vision API의 하한. 커버리지와 최신성의 균형점 |
| iOS 17.0 | 레거시 `VN*` API 강제 → Swift 6 동시성과 충돌 |
| iOS 16.0 | 3D 포즈 불가. 검토 대상 아님 |

## 잠정안

**iOS 17.0**

## 쟁점

문서 작성 시 잠정안이었던 iOS 17.0은 **전제가 틀렸다.** 두 가지를 놓쳤다.

**1. Vision 프레임워크가 Swift 네이티브로 재설계됐다 (WWDC24, iOS 18+)**

기존 `VN*` 클래스는 Apple 공식 문서에서 *"Original Objective-C and Swift API"* 로 분류됐다.

| | 레거시 `VNDetectHumanBodyPoseRequest` | 신규 `DetectHumanBodyPoseRequest` |
|---|---|---|
| 가용 | iOS 14+ | **iOS 18.0+** |
| 타입 | class, completion handler | **struct, `Sendable`, async/await** |
| 손 관절 | 별도 요청 필요 | **`detectsHands` 플래그 한 줄** |

- 레거시 API는 클래스 기반 + completion handler라 **Swift 6 strict concurrency와 계속 충돌**한다. 60fps 프레임 파이프라인에서 실질적 마찰이다
- `detectsHands`(holistic body pose)는 테니스에서 특히 중요하다. 라켓 잡은 손의 손목·손 관절이 그립과 임팩트 분석에 직접 쓰인다. iOS 17이면 `VNDetectHumanHandPoseRequest`를 따로 돌려 프레임마다 수동으로 합쳐야 한다

**2. 시점 판단이 빠져 있었다**

현재(2026-09) iOS 26이 현재 버전이고 iOS 27이 곧 출시된다. **iOS 17은 3세대 전이다.** Phase 0~2를 마치면 출시는 2027년이므로 iOS 17 지원은 과도하게 보수적이다.

**3. 커버리지 손실은 감당 가능하다**

[ADR-0001](../adr/ADR-0001-hybrid-inference.md)의 온디바이스 우선 구조상 애초에 최신 기기 성능을 요구하는 앱이다. 구형 기기에서는 60fps 실시간 추론 자체가 성립하지 않으므로, 낮은 타깃을 잡아도 실사용이 어렵다.

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-02](./D-02-ui-framework.md), [D-03](./D-03-architecture-pattern.md), [D-08](./D-08-local-db.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)

## 결정

**최소 타깃을 iOS 26.0으로 한다.**

## 근거

- **레거시 분기를 만들지 않는다.** iOS 18을 잡으면 신규 Vision API는 쓸 수 있지만, 이후 iOS 26에 추가된 API를 쓸 때마다 `if #available` 분기와 폴백 경로가 생긴다. 1인 개발에서 이중 경로는 그 자체로 비용이다
- **최신 API를 제약 없이 쓴다.** Vision·SwiftUI·Core ML·Swift Concurrency 전부 최신 형태로 시작한다
- **커버리지 손실을 수용한다.** 출시 시점(2027년) 기준 iOS 26+ 커버리지는 85~90%대로 예상되며, 애초에 실시간 온디바이스 추론이 가능한 기기는 그 범위 안에 있다

### 확정에 따라 함께 결정된 것

| 항목 | 내용 |
|---|---|
| Vision API | 신규 Swift API (`DetectHumanBodyPoseRequest`, `DetectTrajectoriesRequest`) 사용. 레거시 `VN*` 미사용 |
| 손 관절 | `detectsHands = true`로 body + hands를 한 요청에서 획득 |
| 상태 관리 | `@Observable` 사용 가능 |
| 영속화 | SwiftData 사용 가능 ([D-08](./D-08-local-db.md) 판단 시 반영) |
| 카메라 회전 | `AVCaptureDevice.RotationCoordinator` 사용 |

### 후속 결정에 넘길 관찰

문서를 확인하며 나온 사실 중 다른 결정에 영향을 주는 것:

- `HumanBodyPoseObservation`이 **`Codable`을 준수**한다 → [D-09 직렬화](./D-09-serialization.md)에서 재검토할 여지
- `HumanBodyPoseObservation.keypoints`가 **Core ML 호환 multi-array**로 제공된다 → [D-10 스윙 분류 모델](./D-10-swing-classifier.md)에서 Action Classifier 입력으로 직결 가능

---

[← 결정 현황](../DECISION-LOG.md)
