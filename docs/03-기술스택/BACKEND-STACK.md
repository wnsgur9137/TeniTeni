---
title: "백엔드 기술 스택"
aliases: ["백엔드 기술 스택", "Backend Stack"]
tags:
  - 문서유형/설계
  - 영역/백엔드
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 06. 백엔드 기술 스택

> 이 문서의 모든 항목은 [stack-decisions.md](../05-결정/DECISION-LOG.md)에서 순차적으로 확정합니다.

## 6.1 백엔드가 담당하는 것

[02. 시스템 아키텍처](../02-설계/ARCHITECTURE.md)의 하이브리드 구조에 따라, 백엔드의 책임은 다음으로 한정됩니다.

| 책임 | 설명 | 필수 시점 |
|---|---|---|
| 인증 | Sign in with Apple 검증, 세션 토큰 발급 | Phase 2 |
| 클립 업로드 | presigned URL 발급, 업로드 완료 처리 | Phase 2 |
| 비동기 분석 | 큐 기반 정밀 재분석 | Phase 2 |
| 리포트 | 분석 결과 집계, 진척도 산출 | Phase 2 |
| 레퍼런스 | 프로 스윙 라이브러리 제공 | Phase 3 |
| 모델 배포 | Core ML 모델 원격 업데이트 | Phase 3 |

**백엔드가 담당하지 않는 것**: 실시간 추론. 절대 하지 않습니다.

## 6.2 언어 선택

✅ **확정** — **Python 단일 언어** — [D-14](../05-결정/stack/D-14-backend-framework.md)

### 근거

ML 파이프라인은 Python 외의 선택지가 사실상 없습니다. 따라서 API를 다른 언어로 쓰면 **서비스를 두 개 유지**해야 합니다. 1인 개발에서 이 비용은 치명적입니다.

### 후보 비교

| 후보 | 장점 | 단점 | 판단 |
|---|---|---|---|
| **Python (FastAPI)** | ML과 언어 통일, OpenAPI 자동 생성, 개발 속도 | 런타임 성능, 타입 안정성이 정적 언어보다 약함 | ✅ **확정** |
| Kotlin/Spring Boot | 타입 안정성, 성숙한 생태계 | ML과 언어 분리 → 파이프라인 이중 관리 | ❌ |
| Node/NestJS | 개발 속도, TS 타입 | ML 라이브러리 부재 → 결국 Python 서비스 추가 필요 | ❌ |
| Go | 성능, 배포 단순 | 동일한 ML 분리 문제 | ❌ |
| **Vapor (Swift)** | iOS와 언어 통일, 도메인 모델 공유 가능 | ML 워커를 Python으로 따로 두어야 함 | ❌ |

> ✅ **확정** — Vapor의 도메인 모델 공유 이점보다 ML 워커 이중 운영 비용이 큽니다. 메트릭 계산식이 Swift·Python 양쪽에 생기는 문제는 **골든 테스트로 결과 일치를 검증**해 대응합니다.

## 6.3 스택 요약

| 영역 | 잠정안 | 상태 | 대안 |
|---|---|---|---|
| 런타임 | Python 3.12 | ✅ | [D-14](../05-결정/stack/D-14-backend-framework.md) |
| 웹 프레임워크 | FastAPI | ✅ | [D-14](../05-결정/stack/D-14-backend-framework.md) |
| 검증/직렬화 | Pydantic v2 | 🟡 | — |
| ORM | SQLAlchemy 2.0 | 🟡 | SQLModel, Tortoise |
| 마이그레이션 | Alembic | 🟡 | — |
| DB | PostgreSQL 16 | ✅ | [D-16](../05-결정/stack/D-16-database.md). TimescaleDB 미사용 |
| 큐 | **arq** + Redis | ✅ | [D-17](../05-결정/stack/D-17-task-queue.md) |
| 오브젝트 스토리지 | Cloudflare R2 | ⬜ | AWS S3, Supabase Storage |
| 인증 | Sign in with Apple + 자체 JWT | ⬜ | Firebase Auth, Supabase Auth |
| 패키지 관리 | uv | ⬜ | poetry, pdm |
| 린트/포맷 | ruff | 🟡 | black + flake8 |
| 타입 체크 | mypy | 🟡 | pyright |
| 테스트 | pytest | 🟡 | — |
| 컨테이너 | Docker + Compose | 🟡 | — |
| 배포 | 단일 VM → 필요 시 확장 | ⬜ | Fly.io, Railway, AWS ECS |
| 관측 | Sentry + OpenTelemetry | ⬜ | Grafana Cloud |

## 6.4 ML 스택

| 영역 | 잠정안 | 상태 |
|---|---|---|
| 프레임워크 | PyTorch 2.x | 🟡 |
| 공 검출 | TrackNetV2/V3 | ⬜ |
| 포즈 | MMPose (ViTPose / HRNet) | ⬜ |
| 3D 리프팅 | MotionBERT 계열 | ⬜ |
| 고전 CV | OpenCV (코트 라인, 호모그래피) | 🟡 |
| 수치 후처리 | NumPy, SciPy (칼만, 궤적 피팅) | ✅ |
| Core ML 변환 | coremltools | 🟡 |
| 실험 관리 | MLflow 또는 W&B | ⬜ |
| 데이터 버전 | DVC | ⬜ |
| 모델 서빙 | 워커 프로세스 내 직접 로드 | 🟡 |

**모델 서빙에 대해**: 초기에는 TorchServe나 Triton을 도입하지 않습니다. arq 워커가 시작 시 모델을 메모리에 올려두고(`on_startup`) 직접 추론하는 것이 가장 단순합니다. 동시 처리량이 문제가 될 때 분리합니다.

## 6.5 검토했으나 채택하지 않은 대안: BaaS

❌ **미채택** — [D-15](../05-결정/stack/D-15-baas-vs-selfhosted.md) (2026-09-10)

```
Supabase (Auth + PostgreSQL + Storage + Realtime)
    +
Python 분석 워커 1개 (직접 운영)
```

**이점**
- API 레이어를 통째로 걷어냄. Phase 2를 수 주 단축
- 인증, 스토리지, RLS를 직접 구현하지 않음
- 앱은 Supabase Swift SDK로 직접 접근

**비용**
- 비즈니스 로직이 클라이언트와 DB 함수로 분산됨
- 벤더 종속. 다만 PostgreSQL 기반이라 이관 경로는 열려 있음
- swift-openapi-generator 기반 계약 검증의 이점을 잃음

**미채택 이유**: 진척도 집계와 레퍼런스 DTW 비교 등 서버 로직이 Phase 3에서 늘어납니다. 그 시점에 로직이 클라이언트와 DB 함수로 흩어지는 비용이, Phase 2를 수 주 단축하는 이득보다 큽니다.

## 6.6 API 설계 원칙

- **OpenAPI가 단일 진실 공급원(SSOT)** — `contracts/openapi.yaml`. FastAPI가 생성하고, iOS 클라이언트가 소비
- **긴 작업은 반드시 비동기** — 영상 분석은 수십 초 단위. 동기 응답 금지. `202 Accepted` + 상태 폴링/푸시. arq는 모니터링 UI가 없으므로 `clips.analysis_state`를 DB에서 관리해 노출한다
- **영상은 API 서버를 경유하지 않음** — presigned URL로 클라이언트가 스토리지에 직접 업로드
- **멱등성** — 업로드 완료, 분석 요청은 재시도 안전하게 설계
- **버저닝** — `/v1/` 프리픽스. 앱 배포 주기가 서버보다 느리므로 하위 호환 필수

### 주요 엔드포인트 (초안)

```
POST   /v1/auth/apple              Apple ID 토큰 → 세션 토큰
POST   /v1/auth/refresh

GET    /v1/sessions
POST   /v1/sessions
GET    /v1/sessions/{id}

POST   /v1/clips                   → clipId + presigned upload URL
POST   /v1/clips/{id}/complete     → 분석 큐 등록 (202)
GET    /v1/clips/{id}
GET    /v1/clips/{id}/analysis
DELETE /v1/clips/{id}

GET    /v1/swings/{id}
GET    /v1/swings/{id}/feedback

GET    /v1/references?type=forehand
GET    /v1/progress?from=&to=
```

## 6.7 파일 구조

```
server/
├── pyproject.toml
├── uv.lock
├── src/teniteni/
│   ├── api/
│   │   ├── main.py                 # FastAPI 앱
│   │   ├── deps.py                 # 의존성 주입
│   │   ├── errors.py
│   │   └── routers/
│   │       ├── auth.py
│   │       ├── sessions.py
│   │       ├── clips.py
│   │       ├── swings.py
│   │       ├── references.py
│   │       └── progress.py
│   ├── core/
│   │   ├── config.py               # pydantic-settings
│   │   ├── security.py             # JWT, Apple 토큰 검증
│   │   └── logging.py
│   ├── db/
│   │   ├── base.py
│   │   ├── session.py
│   │   ├── models/
│   │   │   ├── user.py
│   │   │   ├── session.py
│   │   │   ├── clip.py
│   │   │   ├── swing.py
│   │   │   ├── metrics.py
│   │   │   └── reference.py
│   │   └── migrations/             # Alembic
│   ├── schemas/                    # Pydantic — OpenAPI 원천
│   ├── services/                   # 도메인 로직
│   │   ├── clip_service.py
│   │   ├── analysis_service.py
│   │   └── progress_service.py
│   ├── storage/
│   │   └── object_store.py         # presigned URL
│   └── worker/
│       ├── worker.py               # arq WorkerSettings
│       └── tasks/
│           ├── analyze_clip.py
│           └── generate_report.py
│
├── ml/
│   ├── pipelines/
│   │   ├── ball_tracking.py
│   │   ├── pose_estimation.py
│   │   ├── pose_3d_lifting.py
│   │   └── court_detection.py
│   ├── models/                     # 정의 + 체크포인트 로더
│   ├── postprocess/
│   │   ├── kalman.py
│   │   ├── trajectory_fit.py
│   │   └── metrics.py
│   └── export/
│       └── to_coreml.py            # PyTorch → Core ML 변환
│
├── tests/
│   ├── api/
│   ├── services/
│   ├── ml/
│   └── fixtures/                   # 샘플 영상 (DVC)
│
└── docker/
    ├── Dockerfile.api
    ├── Dockerfile.worker
    └── compose.yml
```

## 6.8 인프라 계획

**Phase 2 (초기)**
- 단일 VM에 Docker Compose로 API + arq 워커 + Postgres + Redis
- GPU 없이 CPU 추론으로 시작. 처리 시간이 길어도 비동기라 허용 가능
- 스토리지만 Cloudflare R2 (egress 무료가 영상 서비스에 결정적)

**Phase 3 (확장 시)**
- 워커만 GPU 인스턴스로 분리 (RunPod / Lambda Labs / AWS g5)
- DB는 관리형으로 이전 (Neon / Supabase / RDS)
- IaC는 이 시점에 Terraform 도입 검토

⬜ **결정 필요** — GPU가 실제로 필요한지는 [03. 비전 파이프라인](../02-설계/VISION-PIPELINE.md) 3.2절의 "서버 정밀 분석이 온디바이스 대비 유의미한가" 검증 결과에 달려 있습니다. 차이가 작으면 서버 ML 자체를 축소합니다.

## 관련 문서

- [시스템 아키텍처](../02-설계/ARCHITECTURE.md)
- [비전 파이프라인](../02-설계/VISION-PIPELINE.md)
- [저장소 구조](../03-기술스택/REPOSITORY.md)
- [결정 현황](../05-결정/DECISION-LOG.md)

---

[← 문서 허브](../INDEX.md)
