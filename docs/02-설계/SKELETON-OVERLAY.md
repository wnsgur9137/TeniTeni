---
title: "스켈레톤 오버레이"
aliases: ["스켈레톤 오버레이", "Skeleton Overlay"]
tags:
  - 문서유형/설계
  - 영역/비전
  - 영역/iOS
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 04. 스켈레톤 오버레이

포즈 추정 결과를 화면에 그리는 설계입니다. 이 화면이 앱의 첫인상이자 신뢰도 그 자체이므로 별도 문서로 다룹니다.

"그냥 선 긋기"로 접근하면 반드시 실패하는 지점이 세 군데 있습니다: **지연**, **좌표 변환**, **떨림**.

## 4.1 렌더링 구조

✅ **확정** — Metal 프리뷰 직접 렌더 ([D-07](../05-결정/stack/D-07-overlay-rendering.md))

`AVCaptureVideoPreviewLayer`를 **사용하지 않습니다.** 같은 `CMSampleBuffer`에서 영상 텍스처와 스켈레톤·궤적을 함께 그립니다.

```
ZStack
├─ MetalCameraView   (UIViewRepresentable → MTKView)   ← 영상 + 스켈레톤 + 궤적
└─ GuideOverlay      (SwiftUI)                          ← 프레이밍 가이드, 흔들림·발열 경고
```

가이드와 경고는 60fps가 필요 없으므로 SwiftUI로 남겨둡니다. [D-02](../05-결정/stack/D-02-ui-framework.md)에서 예상한 `UIViewRepresentable` 경계가 여기입니다.

### 렌더 패스

| 패스 | 내용 |
|---|---|
| `CameraTexturePass` | `CVMetalTextureCache`로 `CMSampleBuffer` → Metal 텍스처, 풀스크린 quad |
| `SkeletonPass` | 본 20개를 라인, 관절 19개를 인스턴싱 원 |
| `TrajectoryPass` | 궤적 점 시퀀스를 스트립으로, 알파 페이드 |

## 4.2 지연 문제 — Metal이 해결하는 것

`AVCaptureVideoPreviewLayer`는 프레임을 **즉시** 화면에 띄웁니다. 반면 Vision 추론 결과는 3~15ms 뒤에 나옵니다. 버퍼 큐까지 더하면 스켈레톤이 **1~3프레임 늦게** 따라옵니다.

일상 동작에서는 보이지 않지만, **초당 30m로 움직이는 테니스 스윙에서는 팔이 스켈레톤 밖으로 완전히 튀어나갑니다.**

Metal 직접 렌더는 이 문제를 구조적으로 없앱니다.

```
CMSampleBuffer (t)
  ├─→ 포즈 추정 ──→ 포즈(t)
  └─→ 텍스처 보관
                    ↓ 둘이 준비되면 함께 draw
                  프레임(t) 렌더  ← 영상과 스켈레톤이 같은 시각
```

**영상 표시를 추론 결과에 맞춰 지연시키는 방식**입니다. 화면 전체가 3~15ms 늦어지지만, 영상과 오버레이가 어긋나지 않습니다. 사람은 절대 지연보다 **둘 사이의 어긋남**을 훨씬 잘 인지합니다.

### 프레임 예산 초과 시

분석이 밀리면 [D-04](../05-결정/stack/D-04-concurrency.md)의 스트림 분리 정책을 따릅니다. 오버레이 스트림은 `.bufferingNewest(1)`이므로 오래된 프레임이 버려지고, 렌더는 **가장 최근에 포즈가 준비된 프레임**을 그립니다.

## 4.3 좌표 변환 — 단일 변환 행렬

Vision은 **정규화 좌표 + 좌하단 원점**, Metal NDC는 **-1~1 + 좌하단 원점**입니다. 여기에 aspect-fill 크롭, 디바이스 회전, 전면 카메라 미러링이 겹칩니다.

`layerPointConverted(fromCaptureDevicePoint:)`를 쓸 수 없으므로 **변환 행렬을 직접 만들되, 카메라 텍스처와 관절 좌표에 같은 행렬을 적용합니다.**

```
버퍼 크기 + 뷰 크기      → aspect-fill 스케일
RotationCoordinator     → 회전
카메라 위치             → 미러링
        ↓
   단일 변환 행렬 (single source of truth)
        ├─→ 카메라 텍스처 quad 정점
        └─→ 관절·궤적 정점
```

**두 곳이 같은 행렬을 쓰므로 어긋날 수 없습니다.** 레이어에 물어보던 방식보다 오히려 안전합니다.

```swift
// VisionKit/Render/RenderTransform.swift
import simd
import AVFoundation

struct RenderTransform: Sendable {
    /// 정규화 이미지 좌표(0~1, 좌상단 원점) → NDC(-1~1)
    let matrix: simd_float4x4

    init(bufferSize: CGSize, viewSize: CGSize,
         rotationAngle: CGFloat, isMirrored: Bool) {
        // 1. aspect-fill 스케일 — 짧은 축을 채우고 긴 축을 넘치게
        let bufferAspect = Float(bufferSize.width / bufferSize.height)
        let viewAspect = Float(viewSize.width / viewSize.height)
        var sx: Float = 1, sy: Float = 1
        if bufferAspect > viewAspect {
            sx = bufferAspect / viewAspect     // 좌우가 넘침
        } else {
            sy = viewAspect / bufferAspect     // 상하가 넘침
        }

        // 2. 0~1 → -1~1, y축 뒤집기 (이미지는 y-down, NDC는 y-up)
        var m = simd_float4x4(diagonal: .init(2 * sx, -2 * sy, 1, 1))
        m.columns.3 = .init(-sx, sy, 0, 1)

        // 3. 회전
        let r = simd_float4x4(rotationZ: Float(rotationAngle * .pi / 180))
        m = r * m

        // 4. 전면 카메라 미러링
        if isMirrored {
            m = simd_float4x4(diagonal: .init(-1, 1, 1, 1)) * m
        }
        self.matrix = m
    }

    /// Vision 정규화 좌표(좌하단 원점) → NDC
    func ndc(visionPoint p: CGPoint) -> SIMD2<Float> {
        // Vision은 y-up이므로 이미지 좌표계로 뒤집어서 넣는다
        let v = matrix * SIMD4<Float>(Float(p.x), Float(1 - p.y), 0, 1)
        return .init(v.x, v.y)
    }
}
```

`AVCaptureDevice.RotationCoordinator`(iOS 17+)로 `videoRotationAngle`을 추종합니다. [D-01](../05-결정/stack/D-01-deployment-target.md)에서 iOS 26을 확정했으므로 제약 없이 사용합니다.

> **주의**: 관절 좌표를 CPU에서 NDC로 변환해 정점 버퍼에 넣어도 되고, 정규화 좌표를 그대로 넣고 셰이더에서 행렬을 곱해도 됩니다. 관절이 19개뿐이라 어느 쪽이든 비용 차이는 없습니다. **행렬을 uniform으로 넘겨 셰이더에서 적용하는 쪽**이 텍스처와 확실히 같은 변환을 쓰게 되므로 권장합니다.

## 4.4 스켈레톤 정의

```swift
// VisionKit/Pose/PoseSkeleton.swift
// iOS 26 타깃이므로 신규 Swift Vision API를 사용한다 (레거시 VN* 아님)
import Vision

enum BodyPart: CaseIterable {
    case face, torso, leftArm, rightArm, leftLeg, rightLeg
}

struct Bone {
    let from: HumanBodyPoseObservation.JointName
    let to: HumanBodyPoseObservation.JointName
    let part: BodyPart
}

enum PoseSkeleton {
    static let bones: [Bone] = [
        // 얼굴
        .init(from: .nose,     to: .leftEye,   part: .face),
        .init(from: .leftEye,  to: .leftEar,   part: .face),
        .init(from: .nose,     to: .rightEye,  part: .face),
        .init(from: .rightEye, to: .rightEar,  part: .face),
        // 몸통
        .init(from: .neck,          to: .leftShoulder,  part: .torso),
        .init(from: .neck,          to: .rightShoulder, part: .torso),
        .init(from: .neck,          to: .root,          part: .torso),
        .init(from: .leftShoulder,  to: .leftHip,       part: .torso),
        .init(from: .rightShoulder, to: .rightHip,      part: .torso),
        .init(from: .leftHip,       to: .root,          part: .torso),
        .init(from: .rightHip,      to: .root,          part: .torso),
        // 팔
        .init(from: .leftShoulder,  to: .leftElbow,  part: .leftArm),
        .init(from: .leftElbow,     to: .leftWrist,  part: .leftArm),
        .init(from: .rightShoulder, to: .rightElbow, part: .rightArm),
        .init(from: .rightElbow,    to: .rightWrist, part: .rightArm),
        // 다리
        .init(from: .leftHip,   to: .leftKnee,   part: .leftLeg),
        .init(from: .leftKnee,  to: .leftAnkle,  part: .leftLeg),
        .init(from: .rightHip,  to: .rightKnee,  part: .rightLeg),
        .init(from: .rightKnee, to: .rightAnkle, part: .rightLeg),
    ]
}

/// 렌더링 직전 상태. 정규화 좌표를 유지하고 변환은 셰이더에서 한다.
struct RenderablePose: Sendable {
    struct Joint: Sendable {
        let normalized: CGPoint     // Vision 정규화 좌표
        let confidence: Float
        let issue: JointIssue?      // 교정 대상 여부
    }
    var joints: [HumanBodyPoseObservation.JointName: Joint]
    var hands: HandOverlay?         // detectsHands 결과 (라켓 손 강조용)
    var phase: SwingPhase?          // 임팩트 순간 강조용
    var timestamp: CMTime           // 짝이 되는 프레임 식별용
}
```

## 4.5 정점 생성

관절 19개 · 본 20개는 매 프레임 정점 버퍼를 새로 채워도 부담이 없습니다.

```swift
// VisionKit/Render/SkeletonPass.swift
struct SkeletonVertex {
    var position: SIMD2<Float>   // 정규화 좌표 (셰이더에서 변환)
    var color: SIMD4<Float>
}

func buildBoneVertices(_ pose: RenderablePose,
                       style: SkeletonStyle) -> [SkeletonVertex] {
    var out: [SkeletonVertex] = []
    out.reserveCapacity(PoseSkeleton.bones.count * 2)

    for bone in PoseSkeleton.bones {
        guard let a = pose.joints[bone.from],
              let b = pose.joints[bone.to],
              a.confidence > style.minConfidence,
              b.confidence > style.minConfidence else { continue }

        // 신뢰도 → 투명도. 가려진 관절이 흐려지면 사용자가 스스로 카메라를 고친다
        let alpha = min(a.confidence, b.confidence)
        var color = style.color(for: bone.part)
        color.w *= alpha

        out.append(.init(position: .init(Float(a.normalized.x), Float(a.normalized.y)),
                         color: color))
        out.append(.init(position: .init(Float(b.normalized.x), Float(b.normalized.y)),
                         color: color))
    }
    return out
}
```

셰이더에서 `RenderTransform.matrix`를 uniform으로 받아 적용합니다.

```metal
// Shaders.metal
vertex VertexOut skeleton_vertex(const device SkeletonVertex* v [[buffer(0)]],
                                 constant float4x4& transform [[buffer(1)]],
                                 uint vid [[vertex_id]]) {
    VertexOut out;
    // Vision은 y-up이므로 이미지 좌표계로 뒤집어 넣는다
    float2 p = float2(v[vid].position.x, 1.0 - v[vid].position.y);
    out.position = transform * float4(p, 0.0, 1.0);
    out.color = v[vid].color;
    return out;
}
```

> 선 굵기: Metal의 라인 프리미티브는 굵기를 지정할 수 없습니다. **본을 사각형(quad)으로 확장**해 그려야 원하는 두께가 나옵니다. 관절 원도 인스턴싱된 quad + 프래그먼트 셰이더에서 원형 마스크로 처리합니다.

## 4.6 떨림 제거 — One Euro Filter

Vision 원본 출력은 **정지 상태에서도 관절이 2~5px씩 떱니다.** 그대로 그리면 아마추어처럼 보입니다.

단순 이동평균은 빠른 스윙에서 지연을 만들므로, **속도에 따라 컷오프 주파수가 변하는 One Euro Filter**가 정답입니다. 느릴 때는 강하게 평활화하고 빠를 때는 반응성을 살립니다.

```swift
// VisionKit/Pose/OneEuroFilter.swift
struct OneEuroFilter {
    var minCutoff: Double = 1.0    // 정지 시 안정성 ↑ (낮게)
    var beta: Double = 0.02        // 빠른 동작 반응성 ↑ (테니스는 크게)
    var dCutoff: Double = 1.0

    private var xPrev: Double?
    private var dxPrev: Double?
    private var yPrev: Double?
    private var tPrev: TimeInterval?

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func filter(_ x: Double, at t: TimeInterval) -> Double {
        defer { xPrev = x; tPrev = t }
        guard let tPrev, let xPrev, let yPrev else { yPrev = x; return x }

        let dt = max(t - tPrev, 1e-4)
        let dx = (x - xPrev) / dt
        let aD = alpha(cutoff: dCutoff, dt: dt)
        let edx = aD * dx + (1 - aD) * (dxPrev ?? dx)
        dxPrev = edx

        let cutoff = minCutoff + beta * abs(edx)
        let a = alpha(cutoff: cutoff, dt: dt)
        let y = a * x + (1 - a) * yPrev
        self.yPrev = y
        return y
    }
}
```

관절 19개 × (x, y) = **필터 인스턴스 38개**를 유지합니다.

`beta` 튜닝은 실제 스윙 영상으로 해야 합니다:
- 너무 낮으면 → 임팩트 순간 손목이 잘려 보임 (지연)
- 너무 높으면 → 떨림이 남음

confidence가 임계값 아래로 떨어진 관절은 필터를 갱신하지 않고 마지막 값을 유지하거나, 일정 프레임 이상 지속되면 표시를 중단합니다.

## 4.7 시각화 원칙

여기가 경쟁 앱과 갈리는 지점입니다. 흰 선만 그리는 건 데모지 제품이 아닙니다.

| 요소 | 설계 | 목적 |
|---|---|---|
| **부위별 컬러** | 라켓 팔은 강조색, 나머지는 저채도 | 시선을 어디에 둘지 알려줌 |
| **신뢰도 → 투명도** | confidence를 그대로 alpha에 매핑 | 가려진 관절이 흐려지면 사용자가 스스로 카메라 위치를 고침. **에러 메시지보다 강력함** |
| **문제 관절 강조** | 빨강 원 + 각도 라벨 | 룰 엔진이 잡은 이탈 관절만. 3개 넘게 띄우면 아무도 안 봄 |
| **모션 트레일** | 최근 N프레임 손목 궤적을 잔상으로 | 스윙 경로가 한눈에 들어옴. Metal에서는 링 버퍼 정점으로 거의 무료 |
| **페이즈 강조** | 임팩트 프레임에서 스켈레톤 펄스 | 결정적 순간을 인지시킴 |
| **레퍼런스 고스트** | 프로 스켈레톤을 반투명으로 겹침 | **킬러 기능.** 단, 신체 비율 정규화 선행 필요 → Phase 2 |

각도 라벨 같은 텍스트는 Metal에서 직접 그리기 번거로우므로, **`GuideOverlay`(SwiftUI)에 올려 관절 화면 좌표로 배치**합니다. 라벨은 초당 60회 갱신할 필요가 없습니다.

### 레퍼런스 고스트의 선결 과제

프로 선수 스켈레톤을 그냥 겹치면 체격 차이 때문에 전혀 맞지 않습니다.
1. 어깨너비 또는 신장 기준 스케일 정규화
2. 골반(root) 기준 위치 정렬
3. DTW로 시간축 정렬 (스윙 속도가 다르므로)

## 4.8 녹화 영상 합성

Metal 렌더 경로를 **그대로 재사용**합니다. 화면 대신 오프스크린 텍스처에 그려 `AVAssetWriterInputPixelBufferAdaptor`로 넘깁니다.

이것이 [D-07](../05-결정/stack/D-07-overlay-rendering.md)에서 Canvas 대신 Metal을 택한 두 번째 이유입니다. Canvas였다면 합성용 렌더러를 따로 만들어야 했습니다.

## 4.9 파일 배치

```
Projects/
├── VisionKit/Sources/
│   ├── Pose/
│   │   ├── PoseEstimator.swift          # DetectHumanBodyPoseRequest 래핑
│   │   ├── PoseSkeleton.swift           # Bone 정의
│   │   ├── OneEuroFilter.swift          # 떨림 제거
│   │   ├── PoseSmoother.swift           # 관절별 필터 관리
│   │   └── JointAngle.swift             # 각도 계산 → 교정 판정 입력
│   └── Render/
│       ├── FrameRenderer.swift          # Metal 파이프라인 총괄
│       ├── CameraTexturePass.swift      # CVMetalTextureCache
│       ├── SkeletonPass.swift           # 본·관절 정점 생성
│       ├── TrajectoryPass.swift         # 궤적 트레일
│       ├── RenderTransform.swift        # ★ 단일 변환 행렬
│       ├── RenderablePose.swift         # 렌더 직전 모델
│       ├── OffscreenRenderer.swift      # 녹화 합성용
│       ├── Shaders.metal
│       └── SkeletonStyle.swift          # 컬러·굵기 토큰
│
└── Features/Capture/Sources/
    ├── View/
    │   └── MetalCameraView.swift        # UIViewRepresentable → MTKView
    └── Overlay/
        └── GuideOverlay.swift           # SwiftUI. 가이드·경고·각도 라벨
```

`VisionKit`은 SwiftUI를 import하지 않으므로 샘플 영상 기반 회귀 테스트가 가능합니다. `OffscreenRenderer`를 쓰면 **렌더 결과 자체를 스냅샷 테스트**할 수도 있습니다.

## 4.10 Phase 0 검증 항목

- [ ] `MTKView` + `CVMetalTextureCache`로 카메라 영상이 60fps로 표시되는가
- [ ] `RenderTransform`이 세로/가로, 전면/후면에서 모두 정확한가
- [ ] 스켈레톤이 몸과 어긋나지 않는가 (빠른 스윙에서)
- [ ] One Euro `beta` 튜닝 — 임팩트 순간 손목이 잘리지 않는가
- [ ] 프레임 예산 내에 렌더가 끝나는가 (목표 1~2ms)

## 관련 문서

- [비전 파이프라인](../02-설계/VISION-PIPELINE.md)
- [iOS 기술 스택](../03-기술스택/IOS-STACK.md)
- [D-07 오버레이 렌더링](../05-결정/stack/D-07-overlay-rendering.md)
- [D-06 포즈 추정 엔진](../05-결정/stack/D-06-pose-engine.md)
- [D-04 비동기 / 상태 관리](../05-결정/stack/D-04-concurrency.md)

---

[← 문서 허브](../INDEX.md)
