---
title: "D-07 오버레이 렌더링"
aliases: ["D-07", "오버레이 렌더링"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-07
status: decided
group: "B. 비전 파이프라인"
depends_on: ["D-02", "D-06"]
affects: []
decide_by: "Phase 0"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Metal (프리뷰 직접 렌더)
---

# D-07. 오버레이 렌더링

> **상태** ✅ **확정 — Metal (프리뷰 직접 렌더)** (2026-09-10) · **그룹** B. 비전 파이프라인

## 질문

스켈레톤·궤적 오버레이를 무엇으로 그릴 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| SwiftUI Canvas | 관절 19개엔 충분. 구현 빠름 |
| CAShapeLayer | 무난. 매 프레임 path 재생성 비용 |
| Metal | 프리뷰 직접 렌더 → 지연 0. 구현 비용 큼 |

## 잠정안

**SwiftUI Canvas → Phase 1에 Metal 전환**

## 쟁점

- 핵심은 **지연 문제**다. 프리뷰 레이어 위에 오버레이하면 스켈레톤이 1~3프레임 늦는다
- 테니스 스윙 속도에서는 팔이 스켈레톤 밖으로 튀어나간다
- Metal로 프리뷰를 직접 렌더해야 지연이 0이 된다
- 중간 단계로 속도 외삽(extrapolation)을 쓸 수 있다

## 의존 관계

- **선행 결정**: [D-02](./D-02-ui-framework.md), [D-06](./D-06-pose-engine.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [스켈레톤 오버레이](../../02-설계/SKELETON-OVERLAY.md)

## 결정

**처음부터 Metal로 프리뷰를 직접 렌더한다.** `AVCaptureVideoPreviewLayer`를 쓰지 않는다.

같은 `CMSampleBuffer`에서 영상 텍스처와 스켈레톤·궤적을 함께 그린다.

## 근거

- **지연이 0이 된다.** 프리뷰 레이어 위에 겹치는 방식은 구조적으로 1~3프레임 늦고, 초당 30m로 움직이는 테니스 스윙에서는 팔이 스켈레톤 밖으로 튀어나간다. 속도 외삽은 임시방편일 뿐이다
- **녹화 영상 합성에 그대로 재사용된다.** 스켈레톤을 구운 영상을 만들 때 렌더 경로를 다시 짜지 않아도 된다
- 단계적 전환(Canvas → Metal)은 결국 두 번 작업하는 것이고, 그사이 Canvas 기준으로 쌓인 좌표 변환·시각화 코드를 버리게 된다

## 결과

**Phase 0 기간이 1~2주 늘어난다.** 게이트 판정이 그만큼 늦어지는 것을 감수한다.

### ⚠️ 좌표 변환 방식이 바뀐다

`AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)` 를 쓸 수 없다. 크롭·미러링·회전을 레이어에 물어보던 방법이 사라진다.

대신 **렌더 변환 행렬을 직접 만들고, 영상 텍스처와 관절 좌표에 같은 행렬을 적용한다.**

```
sampleBuffer 크기 + 화면 크기 → aspect-fill 스케일
디바이스 방향(RotationCoordinator) → 회전
전면 카메라 → 미러링
    ↓
단일 변환 행렬 (single source of truth)
    ├─→ 카메라 텍스처 렌더
    └─→ 정규화 관절 좌표 → 화면 좌표
```

**두 곳에 같은 행렬을 쓰므로 어긋날 수 없다.** 레이어에 물어보던 방식보다 오히려 안전하다.

### 렌더 구성

| 요소 | 처리 |
|---|---|
| 카메라 영상 | `CVMetalTextureCache`로 `CMSampleBuffer` → Metal 텍스처, 풀스크린 quad |
| 스켈레톤 | 본 20개를 라인 프리미티브, 관절 19개를 인스턴싱 원 |
| 궤적 트레일 | 점 시퀀스를 스트립으로, 알파 페이드 |
| 가이드·경고 | SwiftUI 오버레이 (60fps 불필요) |

`MTKView`를 `UIViewRepresentable`로 래핑한다. [D-02](./D-02-ui-framework.md)에서 예상한 경계 그대로다.

---

[← 결정 현황](../DECISION-LOG.md)
