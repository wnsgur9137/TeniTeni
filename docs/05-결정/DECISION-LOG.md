---
title: "결정 현황"
aliases: ["결정 현황", "Decision Log", "스택 결정"]
tags:
  - 문서유형/MOC
  - 영역/프로세스
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 결정 현황

설계 문서의 모든 🟡 잠정 / ⬜ 미결 항목을 하나씩 확정하기 위한 허브입니다.

**진행: 21 / 22 확정** (D-20은 '보류'로 확정)

## 확정 요약

| ID | 항목 | 확정안 | 한 줄 근거 |
|---|---|---|---|
| [D-01](./stack/D-01-deployment-target.md) | 최소 iOS 타깃 | **iOS 26.0** | 신규 Swift Vision API 확보 + `if #available` 분기 제거 |
| [D-02](./stack/D-02-ui-framework.md) | UI 프레임워크 | **전면 SwiftUI** | 명령형 영역은 어차피 래핑됨. `Canvas`·Swift Charts는 SwiftUI에서만 공짜 |
| [D-03](./stack/D-03-architecture-pattern.md) | 아키텍처 | **Clean + TCA** | 촬영 화면 상태 얽힘을 Reducer 합성으로 분해 |
| [D-04](./stack/D-04-concurrency.md) | 비동기 | **Swift Concurrency** | 오버레이는 최신성, 궤적은 연속성 → 스트림 분리 |
| [D-06](./stack/D-06-pose-engine.md) | 포즈 엔진 | **Apple Vision** | 의존성 0 + ANE. 발끝은 발목으로 근사 |
| [D-07](./stack/D-07-overlay-rendering.md) | 오버레이 렌더링 | **Metal** | 프리뷰 직접 렌더로 지연 0. Phase 0 +1~2주 |
| [D-08](./stack/D-08-local-db.md) | 로컬 DB | **SwiftData** | 시계열은 파일로 빼 DB 부하가 낮음 |
| [D-09](./stack/D-09-serialization.md) | 시계열 직렬화 | **Protobuf** | Swift·Python 스키마 공유. 좌표 5,700개/스윙 |
| [D-10](./stack/D-10-swing-classifier.md) | 스윙 분류 | **Create ML** | keypoints 직결. 데이터 적은 초기엔 단순 모델이 유리 |
| [D-11](./stack/D-11-networking.md) | 네트워크 | **Moya** | TargetType으로 API 표면 일람. 스텁으로 서버 없이 테스트 |
| [D-12](./stack/D-12-dependency-injection.md) | DI | **swift-dependencies** | TCA 내장이라 추가 의존성 0. 주입 경로 단일화 |
| [D-13](./stack/D-13-observability.md) | 관측 | **Firebase Crashlytics** | 무료 무제한 + 기존 경험. 성능 지표는 자체 수집 |
| [D-14](./stack/D-14-backend-framework.md) | 백엔드 | **Python + FastAPI** | ML과 언어 통일. 서비스 이중화 회피 |
| [D-15](./stack/D-15-baas-vs-selfhosted.md) | 구축 방식 | **자체 구축** | Phase 3 서버 로직 증가 대비. 벤더 종속 없음 |
| [D-16](./stack/D-16-database.md) | 서버 DB | **PostgreSQL 16** | 메타데이터만 저장. TimescaleDB 불필요 |
| [D-17](./stack/D-17-task-queue.md) | 작업 큐 | **arq** | async 네이티브. 작업이 2개뿐이라 Celery는 과함 |
| [D-18](./stack/D-18-object-storage.md) | 스토리지 | **Cloudflare R2** | egress 무료. 영상 반복 다운로드 패턴에 결정적 |
| [D-19](./stack/D-19-authentication.md) | 인증 | **Apple + 자체 JWT** | iOS 단독 앱. 인증까지 벤더 종속시키지 않음 |
| [D-20](./stack/D-20-server-ml.md) | 서버 ML | **⏸ 보류** | 개선폭 미검증. CPU로 시작해 Phase 2에서 정량 비교 |
| [D-21](./stack/D-21-deployment.md) | 인프라 | **단일 VM + Compose** | D-20 보류로 GPU 불필요. 비용·복잡도 최소 |
| [D-05](./stack/D-05-module-tooling.md) | 모듈 빌드 | **Tuist 4** | TCA로 모듈 세트가 늘어 템플릿화 가치 상승 |

### 확정에 따른 고정 사항

- Vision은 신규 Swift API (`DetectHumanBodyPoseRequest`, `detectsHands`) — 레거시 `VN*` 미사용
- 상태는 `@Observable`, 영속화는 SwiftData 가능
- **프레임 스트림은 TCA 바깥** — 60fps를 Reducer 액션으로 흘리지 않는다
- RxSwift 미도입 확정
- Phase 0은 단일 타깃, Phase 1에서 Tuist 모듈화


## 진행 방법

1. 아래 순서대로 한 항목씩 다룹니다. **순서는 의존 관계를 따릅니다** — 앞 항목이 뒤 항목의 선택지를 좁힙니다
2. 각 결정 노트에서 후보·쟁점을 검토하고 결론과 근거를 노트에 기록합니다
3. 확정되면 노트의 프론트매터 `status`를 `decided`로 바꾸고 `decided_on`·`decision`을 채웁니다
4. 영향받는 설계 문서의 상태 표기(🟡 → ✅)도 함께 갱신합니다
5. 되돌리기 어려운 결정은 [adr](./adr/)에 ADR을 추가합니다

## A. iOS 기반 — 다른 모든 것에 영향

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-01](./stack/D-01-deployment-target.md) | 최소 iOS 타깃 버전 | **iOS 26.0** | 2026-09-10 | ✅ |
| [D-02](./stack/D-02-ui-framework.md) | UI 프레임워크 | **전면 SwiftUI** | 2026-09-10 | ✅ |
| [D-03](./stack/D-03-architecture-pattern.md) | 아키텍처 패턴 | **Clean + TCA** | 2026-09-10 | ✅ |
| [D-04](./stack/D-04-concurrency.md) | 비동기 / 상태 관리 | **Swift Concurrency, 스트림 분리** | 2026-09-10 | ✅ |
| [D-05](./stack/D-05-module-tooling.md) | 모듈 빌드 도구 | **Tuist 4** | 2026-09-10 | ✅ |

## B. 비전 파이프라인

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-06](./stack/D-06-pose-engine.md) | 포즈 추정 엔진 | **Apple Vision** | 2026-09-10 | ✅ |
| [D-07](./stack/D-07-overlay-rendering.md) | 오버레이 렌더링 | **Metal (직접 렌더)** | 2026-09-10 | ✅ |
| [D-08](./stack/D-08-local-db.md) | 로컬 데이터베이스 | **SwiftData** | 2026-09-10 | ✅ |
| [D-09](./stack/D-09-serialization.md) | 포즈 시계열 직렬화 | **Protobuf** | 2026-09-10 | ✅ |
| [D-10](./stack/D-10-swing-classifier.md) | 스윙 분류 모델 | **Create ML Action Classifier** | 2026-09-10 | ✅ |

## C. iOS 부가 스택

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-11](./stack/D-11-networking.md) | 네트워크 계층 | **Moya** | 2026-09-10 | ✅ |
| [D-12](./stack/D-12-dependency-injection.md) | 의존성 주입 | **swift-dependencies** | 2026-09-10 | ✅ |
| [D-13](./stack/D-13-observability.md) | 크래시 리포팅 / 분석 | **Firebase Crashlytics** | 2026-09-10 | ✅ |

## D. 백엔드 — Phase 2 직전까지 미뤄도 무방

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-14](./stack/D-14-backend-framework.md) | 백엔드 언어 / 프레임워크 | **Python + FastAPI** | 2026-09-10 | ✅ |
| [D-15](./stack/D-15-baas-vs-selfhosted.md) | 자체 구축 vs BaaS | **FastAPI 자체 구축** | 2026-09-10 | ✅ |
| [D-16](./stack/D-16-database.md) | 데이터베이스 | **PostgreSQL 16** | 2026-09-10 | ✅ |
| [D-17](./stack/D-17-task-queue.md) | 작업 큐 | **arq + Redis** | 2026-09-10 | ✅ |
| [D-18](./stack/D-18-object-storage.md) | 오브젝트 스토리지 | **Cloudflare R2** | 2026-09-10 | ✅ |
| [D-19](./stack/D-19-authentication.md) | 인증 | **Sign in with Apple + 자체 JWT** | 2026-09-10 | ✅ |
| [D-20](./stack/D-20-server-ml.md) | 서버 ML 스택 | **보류 (Phase 2 검증 후)** | 2026-09-10 | ⏸ |
| [D-21](./stack/D-21-deployment.md) | 배포 / 인프라 | **단일 VM + Docker Compose** | 2026-09-10 | ✅ |

## E. 저장소 / 프로세스

| ID | 항목 | 잠정안 / **확정안** | 확정 시점 | 상태 |
|---|---|---|---|---|
| [D-22](./stack/D-22-repository-workflow.md) | 저장소 구조 및 워크플로 | 모노레포 + trunk-based | 첫 커밋 전 | ⬜ |

## 결정 순서

```
D-01 (타깃) → D-02 (UI) → D-03 (아키텍처) → D-04 (비동기) → D-05 (모듈)
     ↓
D-06 (포즈 엔진) → D-07 (렌더링) → D-08 (DB) → D-09 (직렬화) → D-10 (분류 모델)
     ↓
D-11 ~ D-13 (부가 스택)
     ↓
D-22 (저장소) ← Phase 0 시작 가능 지점
     ↓  ... Phase 0 기술 검증 후 ...
D-14 ~ D-21 (백엔드) ← Phase 2 착수 직전에 확정해도 늦지 않음
```

> **백엔드 결정(D-14~D-21)은 서두르지 않아도 됩니다.**
> [ADR-0001](./adr/ADR-0001-hybrid-inference.md)의 오프라인 우선 원칙에 따라 Phase 0/1은 백엔드 없이 진행되며,
> Phase 0의 기술 검증 결과가 백엔드 요구사항 자체를 바꿀 수 있습니다.

## 결정 기록 (ADR)

되돌리기 어렵거나 근거를 남길 가치가 있는 결정만 ADR로 기록합니다.

| # | 제목 | 상태 |
|---|---|---|
| [ADR-0001](./adr/ADR-0001-hybrid-inference.md) | 온디바이스/서버 하이브리드 추론 구조 | Accepted |
| [ADR-0002](./adr/ADR-0002-monorepo.md) | 모노레포 채택 | Proposed |
| [ADR-0003](./adr/ADR-0003-rule-based-evaluation.md) | 자세 평가는 룰 엔진 우선 | Accepted |

ADR 상태: **Proposed**(제안) / **Accepted**(채택) / **Superseded by ADR-XXXX** / **Deprecated**

결정 상태: ✅ 확정 / ⏸ 의도적 보류(재검토 시점 명시) / ⬜ 미결

---

[← 문서 허브](../INDEX.md)
