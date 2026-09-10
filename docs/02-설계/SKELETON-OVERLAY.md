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

"그냥 선 긋기"로 접근하면 반드시 실패하는 지점이 세 군데 있습니다: **좌표 변환**, **지연**, **떨림**.

## 4.1 레이어 구조

```
ZStack
├─ CameraPreview      (UIViewRepresentable → AVCaptureVideoPreviewLayer)
├─ SkeletonOverlay    (SwiftUI Canvas)
├─ TrajectoryOverlay  (SwiftUI Canvas)
└─ GuideOverlay       (프레이밍 가이드, 흔들림 경고)
```

🟡 **잠정** — 렌더링은 SwiftUI `Canvas`

관절 19개 + 본 20개는 Canvas가 60fps로 여유롭게 처리합니다. Metal은 아직 필요 없습니다.

**Metal이 필요해지는 시점**은 두 가지입니다:
1. 녹화 영상에 스켈레톤을 구워 넣을 때 (AVAssetWriter 합성)
2. 4.3절의 지연 문제를 정면으로 해결할 때 (프리뷰를 직접 렌더)

따라서 렌더러는 처음부터 `GraphicsContext`와 `CGContext` 양쪽에서 재사용 가능한 형태로 분리해 둡니다. 그래야 나중에 교체 비용이 한 파일로 끝납니다.

## 4.2 좌표 변환 — 가장 흔한 버그

Vision은 **정규화 좌표 + 좌하단 원점**, UIKit은 **좌상단 원점**입니다. 여기에 `videoGravity = .resizeAspectFill`의 크롭, 전면 카메라 미러링, 디바이스 회전까지 겹칩니다. **직접 계산하면 거의 확실히 틀립니다.**

정답은 `AVCaptureVideoPreviewLayer`에게 물어보는 것입니다. 크롭·미러링·회전을 전부 알아서 처리합니다.

```swift
// VisionKit/Pose/PoseCoordinateMapper.swift
import AVFoundation

@MainActor
struct PoseCoordinateMapper {
    let previewLayer: AVCaptureVideoPreviewLayer

    /// Vision 정규화 좌표(좌하단 원점) → 오버레이 뷰 좌표(좌상단 원점)
    func point(from visionPoint: CGPoint) -> CGPoint {
        // ① Vision(y-up) → capture device 좌표계(y-down)
        let devicePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        // ② videoGravity 크롭 / 미러링 / 회전을 레이어가 반영해 변환
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
    }
}
```

**주의사항**
- `layerPointConverted(fromCaptureDevicePoint:)`는 메인 스레드 전용입니다. 비전 처리는 백그라운드 큐에서 하되 **변환은 메인에서 19개 점만** 수행합니다. 프레임당 19회 변환의 비용은 사실상 0입니다.
- 회전은 iOS 17부터 `AVCaptureConnection.videoRotationAngle`로 설정합니다 (`videoOrientation`은 deprecated). `AVCaptureDevice.RotationCoordinator`를 쓰면 기기 회전을 자동 추종합니다.

## 4.3 지연 — 반드시 인지해야 할 문제

`AVCaptureVideoPreviewLayer`는 프레임을 **즉시** 화면에 띄웁니다. 반면 Vision 추론 결과는 3~15ms 뒤에 나옵니다. 버퍼 큐까지 더하면 스켈레톤은 **1~3프레임 늦게** 따라옵니다.

일상 동작에서는 보이지 않지만, **초당 30m로 움직이는 테니스 스윙에서는 팔이 스켈레톤 밖으로 완전히 튀어나갑니다.**

### 단계별 대응 전략

| 단계 | 방식 | 특징 |
|---|---|---|
| Phase 0 | 프리뷰 레이어 + 오버레이 그대로 | 구현 30분. 느린 동작은 문제없음 |
| Phase 0.5 | **속도 외삽 (extrapolation)** | 마지막 두 프레임의 관절 속도로 예측. 코드 10줄, 체감 개선 큼 |
| Phase 1 | **Metal로 프리뷰 직접 렌더** | 같은 `CMSampleBuffer`에서 영상과 스켈레톤을 함께 그림 → 지연 0. 정석 |
| 리플레이 | 항상 정확 | 오프라인이라 동기화 문제 자체가 없음 |

```swift
// 속도 외삽 — Phase 0.5 임시 대응
func extrapolated(_ current: CGPoint, previous: CGPoint,
                  dt: Double, lead: Double) -> CGPoint {
    guard dt > 0 else { return current }
    let vx = (current.x - previous.x) / dt
    let vy = (current.y - previous.y) / dt
    return CGPoint(x: current.x + vx * lead, y: current.y + vy * lead)
}
// lead = 실측한 추론 지연 (기기별로 캘리브레이션)
```

### 설계 원칙

> **정확한 자세 교정 피드백은 리플레이 화면에서 제공한다.**
> 라이브 오버레이는 "카메라 안에 잘 잡혔다"는 확신을 주는 용도이지,
> 라이브에서 각도를 판정하게 만들면 안 된다.

## 4.4 스켈레톤 정의

```swift
// VisionKit/Pose/PoseSkeleton.swift
import Vision

enum BodyPart: CaseIterable {
    case face, torso, leftArm, rightArm, leftLeg, rightLeg
}

struct Bone {
    let from: VNHumanBodyPoseObservation.JointName
    let to: VNHumanBodyPoseObservation.JointName
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

/// 화면 좌표로 변환이 끝난, 렌더링 직전 상태
struct RenderablePose {
    struct Joint {
        let position: CGPoint
        let confidence: Float
        let issue: JointIssue?      // 교정 대상 여부
    }
    var joints: [VNHumanBodyPoseObservation.JointName: Joint]
    var phase: SwingPhase?          // 임팩트 순간 강조용
}
```

## 4.5 렌더러

```swift
// Features/Capture/Overlay/SkeletonOverlay.swift
import SwiftUI

struct SkeletonOverlay: View {
    let pose: RenderablePose?

    var body: some View {
        Canvas { ctx, _ in
            guard let pose else { return }

            // 본
            for bone in PoseSkeleton.bones {
                guard let a = pose.joints[bone.from],
                      let b = pose.joints[bone.to],
                      a.confidence > 0.3, b.confidence > 0.3 else { continue }

                var path = Path()
                path.move(to: a.position)
                path.addLine(to: b.position)

                let alpha = Double(min(a.confidence, b.confidence))  // 신뢰도 → 투명도
                ctx.stroke(path,
                           with: .color(bone.part.color.opacity(alpha)),
                           style: .init(lineWidth: 4, lineCap: .round))
            }

            // 관절
            for (_, joint) in pose.joints where joint.confidence > 0.3 {
                let r: CGFloat = joint.issue != nil ? 9 : 5
                let rect = CGRect(x: joint.position.x - r,
                                  y: joint.position.y - r,
                                  width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect),
                         with: .color(joint.issue != nil ? .red : .white))

                if let issue = joint.issue {
                    ctx.draw(
                        Text("\(Int(issue.angle))°")
                            .font(.caption2).bold()
                            .foregroundStyle(.red),
                        at: CGPoint(x: joint.position.x, y: joint.position.y - 20)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

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
| **모션 트레일** | 최근 N프레임 손목 궤적을 잔상으로 | 스윙 경로가 한눈에 들어옴 |
| **페이즈 강조** | 임팩트 프레임에서 스켈레톤 펄스 | 결정적 순간을 인지시킴 |
| **레퍼런스 고스트** | 프로 스켈레톤을 반투명으로 겹침 | **킬러 기능.** 단, 신체 비율 정규화 선행 필요 → Phase 2 |

### 레퍼런스 고스트의 선결 과제

프로 선수 스켈레톤을 그냥 겹치면 체격 차이 때문에 전혀 맞지 않습니다. 다음이 필요합니다:
1. 어깨너비 또는 신장 기준 스케일 정규화
2. 골반(root) 기준 위치 정렬
3. DTW로 시간축 정렬 (스윙 속도가 다르므로)

## 4.8 파일 배치

```
Projects/
├── VisionKit/Sources/Pose/
│   ├── PoseEstimator.swift          # VNDetectHumanBodyPoseRequest 래핑
│   ├── PoseSkeleton.swift           # Bone 정의
│   ├── OneEuroFilter.swift          # 떨림 제거
│   ├── PoseSmoother.swift           # 관절별 필터 관리 + 속도 외삽
│   └── JointAngle.swift             # 각도 계산 → 교정 판정 입력
│
└── Features/Capture/Sources/Overlay/
    ├── SkeletonOverlay.swift        # SwiftUI Canvas 렌더러
    ├── PoseCoordinateMapper.swift   # Vision → 뷰 좌표 변환
    ├── RenderablePose.swift         # 렌더 직전 모델
    ├── TrajectoryOverlay.swift      # 공 궤적 (별도 레이어)
    ├── GuideOverlay.swift           # 프레이밍 가이드, 흔들림 경고
    └── SkeletonStyle.swift          # 컬러·굵기 토큰 (DesignSystem 연동)
```

`VisionKit`은 UIKit/SwiftUI를 import하지 않으므로 샘플 영상 기반 회귀 테스트가 가능하고, `Features/Capture/Overlay`는 순수 렌더링만 담당합니다. 이 경계를 지키면 나중에 Metal 렌더러로 교체할 때 `SkeletonOverlay.swift` 한 파일만 바뀝니다.

## 4.9 미결 사항

⬜ **라이브 오버레이와 리플레이 오버레이 중 어느 쪽을 먼저 구현할 것인가**

- 리플레이는 지연 문제가 없어 훨씬 빨리 완성되고, 자세 교정의 실제 가치도 리플레이 쪽에 있음
- 다만 촬영 중 스켈레톤이 안 보이면 "제대로 인식되고 있나" 불안해지므로 라이브는 저품질이라도 있는 편이 나음
- 잠정 결론: **라이브를 최소 품질로 먼저 → 리플레이를 제대로 → 라이브를 Metal로 개선**

## 관련 문서

- [비전 파이프라인](../02-설계/VISION-PIPELINE.md)
- [iOS 기술 스택](../03-기술스택/IOS-STACK.md)
- [D-07 오버레이 렌더링](../05-결정/stack/D-07-overlay-rendering.md)
- [D-06 포즈 추정 엔진](../05-결정/stack/D-06-pose-engine.md)

---

[← 문서 허브](../INDEX.md)
