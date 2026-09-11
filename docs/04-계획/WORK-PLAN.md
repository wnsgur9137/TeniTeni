---
title: "작업 순서"
aliases: ["작업 순서", "Work Plan", "실행 계획"]
tags:
  - 문서유형/계획
  - 영역/제품
created: 2026-09-10
updated: 2026-09-11
status: active
---

# 09. 작업 순서

> **작업 상태는 [GitHub Issues](https://github.com/wnsgur9137/TeniTeni/issues)에 있습니다.**
> 각 단계는 동명의 마일스톤에 대응합니다. 이 문서는 순서와 선행 관계만 담습니다.

[로드맵](ROADMAP.md)이 "무엇을 언제"라면, 이 문서는 **"어떤 순서로, 무엇이 선행인지"** 를 정의합니다.

## 9.1 원칙

**1. 게이트를 최대한 앞으로 당긴다**

Phase 0 게이트(궤적 검출률 70%)가 실패하면 그 위에 쌓은 코드가 상당 부분 무의미해집니다. 게이트 판정에 필요한 최소 코드만 먼저 만듭니다.

**2. 검증은 오프라인으로 한다**

궤적 검출률은 실시간으로 잴 필요가 없습니다. 영상을 찍어두고 나중에 돌려도 같은 값이고, 오히려 **파라미터를 바꿔가며 반복 측정**할 수 있습니다. 코트에 여러 번 나가지 않아도 됩니다.

**3. 모듈은 필요할 때 만든다**

Tuist 모듈을 처음부터 다 나누지 않습니다. **각 모듈은 나눠야 할 구체적 이유가 생겼을 때** 도입합니다 (9.5절).

**4. 백엔드는 Phase 2까지 손대지 않는다**

[ADR-0001](../05-결정/adr/ADR-0001-hybrid-inference.md) 오프라인 우선 원칙. 예외는 두 가지뿐입니다 — Protobuf 스키마(Phase 1)와 CI(Phase 0 말).

## 9.2 전체 타임라인

```
        iOS                                   백엔드
────────────────────────────────────────────────────────────
Phase 0 │ 0-A 정찰      (2~3일)              │ ─
        │ 0-B 촬영      (1일, 코트)          │ ─
        │ 0-C 검증      (1주)  ★ 게이트      │ ─
        │ ─── 게이트 판정 ───                │
        │ 0-D 파이프라인 (2~3주)             │ CI 구축
────────────────────────────────────────────────────────────
Phase 1 │ 1-A 모듈 재편  (3~4일)             │ contracts/proto 확정
        │ 1-B 스윙 검출  (1~2주)             │ ─
        │ 1-C 학습 데이터 (1주, 코트)        │ ─
        │ 1-D 분류·메트릭 (2주)              │ ─
        │ 1-E 리플레이   (1~2주)             │ ─
        │ ─── TestFlight 배포 가능 ───       │
────────────────────────────────────────────────────────────
Phase 2 │ 2-C 업로드·동기화 (1~2주)          │ 2-A 골격  (1주)
        │ 2-E 진척도 화면  (1주)             │ 2-B 인증·스토리지 (1~2주)
        │                                    │ 2-D 워커·분석 (2주)
        │                                    │ ─── D-20 판정 ───
────────────────────────────────────────────────────────────
Phase 3 │ 코트 분석 · 레퍼런스 비교 · 3D 포즈(X-Factor)
```

**Phase 2에서 처음으로 iOS와 백엔드가 병렬**입니다. 그 전까지는 iOS 단독입니다.

---

## 9.3 Phase 0 — 기술 검증

### 0-A. 정찰 (책상, 2~3일)

목표: **실측으로 촬영 프로토콜의 가정을 보정하고, 영상을 찍을 수 있게 만든다.**

| # | 작업 | 산출물 |
|---|---|---|
| 1 | 실기기 지원 포맷 덤프 | 해상도·fps·binned 목록 |
| 2 | 화각 실측 → [촬영 프로토콜 5.1](../02-설계/CAPTURE-PROTOCOL.md#51-카메라-배치) 계산값 보정 | 공 픽셀 크기 실측표 |
| 3 | **최소 촬영 앱** | 프리뷰 + 녹화 버튼 |

최소 촬영 앱의 범위를 엄격히 지킵니다.

- ✅ `activeFormat`으로 1080p120 / 1080p60 선택
- ✅ `setExposureModeCustom` 노출 고정 (1/1000, 1/500, 1/250 전환 가능)
- ✅ 기본 `AVCaptureVideoPreviewLayer` — Metal 아님
- ✅ 녹화 + 촬영 메타(fps·노출·거리) 파일명에 기록
- ❌ 오버레이, 포즈, 궤적, TCA, 모듈 분리 — **전부 없음**

> 단일 타깃 하나면 됩니다. Tuist를 아직 도입하지 않습니다.

### 0-B. 촬영 (코트, 1일)

목표: **조건을 변주한 영상 세트 확보.** 이게 이후 모든 작업의 입력이자 골든 테스트 픽스처가 됩니다.

| 변수 | 값 |
|---|---|
| fps | 120, 60 |
| 노출 | 1/1000, 1/500, 1/250 |
| 거리 | 5m, 6m, 8m |
| 배경 | 단순, 복잡(펜스·관중) |
| 조명 | 실외 맑음 (기준), 실외 흐림 |

각 조합마다 최소 10타구. **기준 조건(실외 맑음·단순 배경·120fps·1/1000·6m)은 30타구 이상.**

> 한 번에 다 못 찍어도 됩니다. 기준 조건부터 확보하고 나머지는 0-C 결과를 보며 추가 촬영합니다.

### 0-C. 오프라인 검증 (책상, 1주) ★ 게이트

목표: **게이트 판정.**

| # | 작업 | 비고 |
|---|---|---|
| 1 | `TeniVision` 모듈 분리 | ✅ 완료 ([SPEC-0005](../07-기획/SPEC-0005-tenivision-module.md)). 단일 타깃 `destinations: [.iPhone, .mac]`로 양쪽 빌드 — 타깃 2개 불필요 |
| 2 | macOS CLI 분석 도구 | `teni analyze`. 영상 → `DetectTrajectoriesRequest` → 결과 JSON. CLI 배치는 [SPEC-0006](../07-기획/SPEC-0006-synthetic-video.md)이 정함 |
| 3 | 임팩트 프레임 라벨링 도구 | 프레임 넘기며 수동 기록. 게이트의 분모 |
| 4 | 파라미터 스윕 | `trajectoryLength`, radius, 노출·거리별 |
| 0 | 합성 영상 생성기 | `teni synth`. 정답을 아는 입력으로 2~4번 도구를 실기기 없이 검증 ([SPEC-0006](../07-기획/SPEC-0006-synthetic-video.md)) |
| 5 | **검출률 집계 및 판정** | [측정 방법](../02-설계/CAPTURE-PROTOCOL.md#55-phase-0-게이트-측정-방법) |

```
Mac ──→ TeniVision (공유) ──→ 검출 결과 JSON ──→ 집계 스크립트 ──→ 판정
        ↑
        └── iOS 앱도 같은 모듈을 쓴다 (0-D부터)
```

**판정**

| 결과 | 다음 |
|---|---|
| ≥ 70% | ✅ 0-D 진행 |
| 50~70% | ⚠️ 파라미터·노출·거리 재튜닝 → 0-B 재촬영 → 재측정 |
| < 50% | ❌ **중단하고 재설계.** [D-20](../05-결정/stack/D-20-server-ml.md) 서버 TrackNet 또는 궤적 기능 v1 제외 |

### 0-D. 실시간 파이프라인 (2~3주) — 게이트 통과 시에만

| # | 작업 | 선행 |
|---|---|---|
| 1 | Metal 프리뷰 직접 렌더 (`MTKView` + `CVMetalTextureCache`) | — |
| 2 | `RenderTransform` 단일 변환 행렬 | 1 |
| 3 | `CMReadySampleBuffer` 기반 프레임 인테이크 + 스트림 분리 | 1 |
| 4 | `DetectHumanBodyPoseRequest` + One Euro Filter | 3 |
| 5 | 스켈레톤 렌더 패스 | 2, 4 |
| 6 | 실시간 궤적 렌더 패스 | 2, 3 |
| 7 | 성능 프로파일링 (120fps 8.3ms 예산) | 5, 6 |
| 8 | 발열·인터럽션·strict concurrency 검증 | 7 |

설계는 [스켈레톤 오버레이](../02-설계/SKELETON-OVERLAY.md)와 [동시성](../02-설계/CONCURRENCY.md)에 있습니다.

**병렬 CI 구축**: 0-D 기간에 `ios.yml`을 만들고, 완료 후 [D-22](../05-결정/stack/D-22-repository-workflow.md)의 브랜치 보호를 강화합니다.

---

## 9.4 Phase 1 — 온디바이스 완결 제품

### 1-A. 모듈 재편 (3~4일)

**Tuist 전면 도입 시점.** 9.5절의 구조로 재편합니다. 여기까지는 `TeniVision` + 앱 타깃 정도만 있었습니다.

### 1-B. 스윙 검출 (1~2주)

- 손목 각속도 기반 룰 트리거 + 히스테리시스
- 링 버퍼 (소급 저장)
- 스윙 구간 클립 저장
- `Domain` 엔티티 확정 (Session, Clip, Swing)

### 1-C. 학습 데이터 촬영 (1주, 코트)

**유형별 200회 이상.** [D-10](../05-결정/stack/D-10-swing-classifier.md)의 진짜 병목입니다. 1-B가 되어야 자동 구간 저장으로 효율이 납니다.

증강(좌우 반전·시간 신축·노이즈)도 이 단계에서 준비합니다.

### 1-D. 분류·메트릭 (2주)

- Create ML Action Classifier 학습 → Core ML 통합
- 페이즈 분할, 임팩트 프레임 특정
- 메트릭 산출 + 룰 엔진 피드백
- **`contracts/proto/` 확정** — 포즈 시계열 저장에 Protobuf 사용 ([D-09](../05-결정/stack/D-09-serialization.md))

> `proto` 스키마는 백엔드보다 먼저 필요합니다. 로컬 저장에 쓰기 때문입니다.

### 1-E. 리플레이·저장 (1~2주)

- SwiftData 영속화
- 슬로우 모션 리플레이 + 스켈레톤 + 페이즈 + 피드백
- 세션 요약, 클립 목록
- 골든 테스트 구축 (0-B 영상을 픽스처로)

**이 시점에 TestFlight 배포가 가능합니다.** 백엔드 없이 앱이 완결됩니다.

---

## 9.5 Phase 2 — 백엔드 연동

**백엔드 착수 조건**: Phase 1 완료. 그전에 서버 코드를 쓰지 않습니다.

### 백엔드 (선행)

| # | 단계 | 내용 |
|---|---|---|
| 2-A | 골격 (1주) | Docker Compose (api·worker·db·redis·caddy), FastAPI 스켈레톤, Alembic 초기 마이그레이션, `contracts/openapi.yaml` 초안 |
| 2-B | 인증·스토리지 (1~2주) | Apple 토큰 검증 + JWT ([D-19](../05-결정/stack/D-19-authentication.md)), R2 presigned URL ([D-18](../05-결정/stack/D-18-object-storage.md)) |
| 2-D | 워커·분석 (2주) | arq 워커, `analyze_clip`, **메트릭 계산식 Python 포팅** |

**메트릭 이중화 검증**: [D-14](../05-결정/stack/D-14-backend-framework.md)에서 약속한 대로, 0-B 영상의 포즈 시계열을 픽스처로 두고 **Swift와 Python 결과가 일치하는지 CI에서 검증**합니다. 이게 없으면 온디바이스 결과와 서버 결과가 조용히 어긋납니다.

### iOS (2-B 이후 병렬)

| # | 단계 | 내용 |
|---|---|---|
| 2-C | 업로드·동기화 (1~2주) | `Network` 모듈 신설, Moya `TargetType`, 백그라운드 업로드, 클립 상태 머신 |
| 2-E | 진척도 (1주) | Swift Charts, 기간별 집계 |

### 2-F. D-20 판정

Phase 2 말에 **서버 정밀 분석이 온디바이스 대비 유의미한지 정량 비교**합니다. 개선폭이 작으면 서버 ML을 도입하지 않고 [D-21](../05-결정/stack/D-21-deployment.md) 인프라가 크게 단순해집니다.

---

## 9.6 Tuist 모듈 구성

### 목표 구조

```
Application     앱 진입점, DI Composition Root, 라우팅
Presentation    화면 단위 TCA Feature (Capture, Analysis, Session, Library, Progress, Onboarding)
Domain          Entity, UseCase, Repository 프로토콜 — 의존성 0
Data            Repository 구현, SwiftData 영속화, 파일 저장소
Network         Moya TargetType, DTO, 인증 인터셉터
TeniVision       분석·렌더 엔진 (Pose / Ball / Render / Swing / Metrics)
DesignSystem    컬러·타이포·공용 컴포넌트
Core            Logger, Extensions, 공용 유틸
```

### 의존성 방향

```
        Application
             │
    ┌────────┼────────┐
Presentation  Data ──→ Network
    │  │       │           │
    │  └──→ Domain ←───────┘
    │          ▲
    │      TeniVision
    │          │
DesignSystem   │
    └────→ Core ←───┘
```

**규칙**

- `Domain`은 아무것도 import하지 않는다 (Foundation 제외)
- `TeniVision`은 `Domain` 엔티티와 `Core`만 안다. **UI를 모른다** → macOS CLI에서 재사용 가능
- `Network`는 `Domain`을 모른다. DTO만 다루고 매핑은 `Data`가 한다
- `Presentation` 내 Feature 간 직접 의존 금지. `Application` 코디네이터 경유
- 프레임 스트림은 `Presentation`이 `TeniVision`을 직접 쓴다 ([D-03](../05-결정/stack/D-03-architecture-pattern.md) TCA 바깥 경로)

### 도입 순서 — 필요할 때 만든다

| 시점 | 도입 | 강제 이유 |
|---|---|---|
| 0-A | (단일 타깃) | 모듈 불필요 |
| **0-C** | **TeniVision** ✅ | **macOS CLI와 iOS 앱이 같은 분석 코드를 써야 함** |
| 0-D | Core | 실시간 파이프라인에서 공용 유틸 발생 |
| **1-A** | **Domain, Data, Presentation, Application, DesignSystem** | TCA Feature가 여러 개 생기는 시점 |
| **2-C** | **Network** | 서버 연동 시작. 그전에 만들면 빈 모듈 |

`Network`를 Phase 1에 만들지 않는 이유는 단순합니다 — **넣을 게 없습니다.**

---

## 9.7 병렬화

| 가능 | 불가 |
|---|---|
| 0-D 파이프라인 ∥ CI 구축 | 0-C 게이트 전에 0-D 착수 (실패 시 매몰) |
| 1-C 학습 데이터 촬영 ∥ 1-D 메트릭 구현 | 1-B 없이 1-C (수동 구간 추출은 비효율) |
| 2-B 이후 백엔드 ∥ iOS 2-C | 2-A 없이 2-C (엔드포인트 미정) |
| 코치 자문 확보 ∥ 전 단계 | — |

**코치 자문은 지금부터 병렬로 진행합니다.** [ADR-0003](../05-결정/adr/ADR-0003-rule-based-evaluation.md)의 룰 임계값을 정할 사람이 필요하고, 리드타임이 가장 깁니다. 1-D 시작 전까지 확보되어야 합니다.

## 9.8 중단·재검토 지점

| 지점 | 조건 | 조치 |
|---|---|---|
| **0-C** | 검출률 < 50% | 접근 재설계. 서버 TrackNet 또는 궤적 기능 v1 제외 |
| 1-D | 분류 정확도 < 90% | 데이터 추가 촬영 → 커스텀 모델 검토 |
| 1-D | 코치 자문 미확보 | 룰 임계값을 문헌 기반 잠정값으로 두고 진행, 출시 전 검증 필수 |
| 2-F | 서버 ML 개선폭 미미 | 서버 ML 미도입. 인프라 단순화 |

## 관련 문서

- [로드맵과 리스크](ROADMAP.md)
- [촬영 프로토콜](../02-설계/CAPTURE-PROTOCOL.md)
- [동시성과 상태 설계](../02-설계/CONCURRENCY.md)
- [iOS 기술 스택](../03-기술스택/IOS-STACK.md)
- [백엔드 기술 스택](../03-기술스택/BACKEND-STACK.md)

---

[← 문서 허브](../INDEX.md)
