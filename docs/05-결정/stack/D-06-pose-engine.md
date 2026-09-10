---
title: "D-06 포즈 추정 엔진"
aliases: ["D-06", "포즈 추정 엔진"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-06
status: decided
group: "B. 비전 파이프라인"
depends_on: []
affects: ["D-07", "D-09", "D-10"]
decide_by: "Phase 0"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Apple Vision (DetectHumanBodyPoseRequest, detectsHands)
---

# D-06. 포즈 추정 엔진

> **상태** ✅ **확정 — Apple Vision** (2026-09-10) · **그룹** B. 비전 파이프라인

## 질문

실시간 포즈 추정을 어떤 엔진으로 할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Apple Vision | 19관절. 의존성 0, ANE 최적화, 무료 |
| MediaPipe Pose (BlazePose) | 33관절. 발끝 포함. 바이너리 크기 증가 |
| MoveNet Thunder | 17관절. 정확도 우위 없음 |
| YOLO-Pose | 다중 인물 강함. 단일 인물에 과함 |

## 잠정안

**Apple Vision**

## 쟁점

- Vision은 19관절이라 **발끝이 없다**. 체중 이동 분석에 발끝이 필요하면 MediaPipe 재검토
- **결정 근거 필요**: 메트릭 목록 중 발끝이 필수인 것이 실제로 있는가
- Vision을 쓰면 스켈레톤 본 정의와 메트릭 계산식이 19관절에 고정된다

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-07](./D-07-overlay-rendering.md), [D-09](./D-09-serialization.md), [D-10](./D-10-swing-classifier.md)

## 영향받는 문서

- [비전 파이프라인](../../02-설계/VISION-PIPELINE.md)
- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

**Apple Vision `DetectHumanBodyPoseRequest`** (신규 Swift API, `detectsHands = true`)

## 근거

- 외부 의존성 0, Neural Engine 가속. [D-04](./D-04-concurrency.md)의 성능 예산에 여유가 생긴다
- `Sendable` 준수 → Swift 6 strict concurrency와 마찰이 없다
- `detectsHands`로 손 관절까지 한 요청에서 얻는다. 라켓 그립·임팩트 분석에 직결
- MediaPipe는 바이너리가 수십 MB 늘고 ANE를 못 써 **발열·배터리(R-5, R-7)를 악화**시킨다. 장시간 촬영 앱에서 이 비용이 크다

### 발끝 부재에 대한 대응

발끝이 필요한 지표는 `weightTransfer`(체중 이동) 하나뿐이며, **발목 중점 대비 골반 수평 이동량으로 근사한다.** Phase 1에서 이 근사가 부정확하다고 판명되면 그때 경량 발 검출 모델 추가를 재검토한다.

---

[← 결정 현황](../DECISION-LOG.md)
