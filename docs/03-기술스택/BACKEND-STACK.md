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

🟡 **잠정** — **Python 단일 언어**

### 근거

ML 파이프라인은 Python 외의 선택지가 사실상 없습니다. 따라서 API를 다른 언어로 쓰면 **서비스를 두 개 유지**해야 합니다. 1인 개발에서 이 비용은 치명적입니다.

### 후보 비교

| 후보 | 장점 | 단점 | 판단 |
|---|---|---|---|
| **Python (FastAPI)** | ML과 언어 통일, OpenAPI 자동 생성, 개발 속도 | 런타임 성능, 타입 안정성이 정적 언어보다 약함 | 🟡 유력 |
| Kotlin/Spring Boot | 타입 안정성, 성숙한 생태계 | ML과 언어 분리 → 파이프라인 이중 관리 | ❌ |
| Node/NestJS | 개발 속도, TS 타입 | ML 라이브러리 부재 → 결국 Python 서비스 추가 필요 | ❌ |
| Go | 성능, 배포 단순 | 동일한 ML 분리 문제 | ❌ |
| **Vapor (Swift)** | iOS와 언어 통일, 도메인 모델 공유 가능 | ML 생태계 없음, 서버 생태계 얕음 | ⬜ 검토 |

> ⬜ **결정 필요** — Vapor는 iOS 개발자에게 매력적이지만 ML 분리 문제가 Spring과 동일합니다. 도메인 모델 공유의 이점이 그 비용을 넘는지 판단 필요.

## 6.3 스택 요약

| 영역 | 잠정안 | 상태 | 대안 |
|---|---|---|---|
| 런타임 | Python 3.12 | 🟡 | 3.13 |
| 웹 프레임워크 | FastAPI | 🟡 | Litestar, Django REST |
| 검증/직렬화 | Pydantic v2 | 🟡 | — |
| ORM | SQLAlchemy 2.0 | 🟡 | SQLModel, Tortoise |
| 마이그레이션 | Alembic | 🟡 | — |
| DB | PostgreSQL 16 | 🟡 | + TimescaleDB 확장 |
| 큐 | Celery + Redis | ⬜ | Dramatiq, arq, RQ |
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

**모델 서빙에 대해**: 초기에는 TorchServe나 Triton을 도입하지 않습니다. Celery 워커가 프로세스 시작 시 모델을 메모리에 올려두고 직접 추론하는 것이 가장 단순합니다. 동시 처리량이 문제가 될 때 분리합니다.

## 6.5 대안 구성: BaaS 우선

⬜ **강력히 검토할 대안** — 1인 개발이라면 현실적입니다.

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

**판단 기준**: Phase 2 착수 시점에 "서버에서 해야 할 비즈니스 로직이 얼마나 되는가"로 결정합니다. 분석 워커 트리거와 결과 조회만이라면 Supabase로 충분합니다.

## 6.6 API 설계 원칙

- **OpenAPI가 단일 진실 공급원(SSOT)** — `contracts/openapi.yaml`. FastAPI가 생성하고, iOS 클라이언트가 소비
- **긴 작업은 반드시 비동기** — 영상 분석은 수십 초 단위. 동기 응답 금지. `202 Accepted` + 상태 폴링/푸시
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
│       ├── celery_app.py
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
- 단일 VM에 Docker Compose로 API + 워커 + Postgres + Redis
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
