---
title: "저장소 구조"
aliases: ["저장소 구조", "Repository"]
tags:
  - 문서유형/설계
  - 영역/인프라
created: 2026-09-10
updated: 2026-09-10
status: active
---

# 07. 저장소 구조

## 7.1 결정: 모노레포

✅ **확정** — 단일 저장소 `wnsgur9137/TeniTeni` — [ADR-0002](../05-결정/adr/ADR-0002-monorepo.md), [D-22](../05-결정/stack/D-22-repository-workflow.md)

### 근거

- **API 계약 변경의 원자성** — 스펙을 바꾸면 iOS와 서버를 한 PR에서 함께 수정할 수 있습니다. 이게 가장 큽니다
- 1인/소규모에서 멀티레포는 순수 비용입니다. 이슈·프로젝트 보드·릴리즈 노트가 흩어집니다
- ML 모델 변경이 iOS(Core ML)와 서버(PyTorch) 양쪽에 동시에 영향을 줍니다

### 비용과 완화

| 비용 | 완화 |
|---|---|
| CI가 전체를 돌면 느림 | GitHub Actions `paths` 필터로 변경 영역만 실행 |
| 저장소 크기 증가 | Git LFS로 모델/샘플 영상 분리, 데이터셋은 DVC 포인터만 |
| 릴리즈 주기 혼선 | 컴포넌트별 태그 프리픽스 (`ios-v*`, `server-v*`) |

### 분리 시점

팀이 3명 이상이 되고 iOS와 서버의 릴리즈 주기가 완전히 갈라질 때 분리합니다. 그전에 쪼개는 것은 손해입니다.

## 7.2 전체 구조

```
TeniTeni/
├── .github/
│   ├── workflows/
│   │   ├── ios.yml                 # paths: ['ios/**']
│   │   ├── server.yml              # paths: ['server/**']
│   │   ├── contracts.yml           # OpenAPI 변경 시 클라이언트 재생성 검증
│   │   ├── ml.yml                  # paths: ['ml/**', 'server/ml/**']
│   │   └── release-ios.yml         # 태그 → Fastlane → TestFlight
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── CODEOWNERS
│   └── dependabot.yml
│
├── ios/                            # → iOS 기술 스택 문서
├── server/                         # → 백엔드 기술 스택 문서
│
├── contracts/                      # ★ 단일 진실 공급원
│   ├── openapi.yaml                # REST API 스펙
│   ├── proto/                      # Protobuf 스키마 (D-09)
│   │   ├── pose.proto
│   │   ├── trajectory.proto
│   │   └── swing.proto
│   └── README.md                   # 생성/소비 절차
│
├── ml/
│   ├── notebooks/                  # 탐색·시각화 (커밋 전 출력 제거)
│   ├── training/
│   │   ├── swing_classifier/       # Create ML / PyTorch 학습
│   │   └── ball_tracker/
│   ├── datasets/                   # DVC 포인터만. 원본 커밋 금지
│   ├── evaluation/                 # 벤치마크 리포트
│   └── README.md
│
├── infra/                          # Phase 3 이후
│   ├── terraform/
│   └── docker/
│
├── docs/                           # Obsidian 볼트 문서 (이 저장소 루트가 볼트)
│   ├── INDEX.md                    # 문서 허브(MOC)
│   ├── _templates/                 # Obsidian 템플릿
│   ├── 01-제품/
│   ├── 02-설계/
│   ├── 03-기술스택/
│   ├── 04-계획/
│   ├── 05-결정/
│   │   ├── DECISION-LOG.md         # 결정 현황 허브
│   │   ├── adr/                    # ADR
│   │   └── stack/                  # 기술 결정 D-01~D-22
│   └── 90-첨부/                    # 이미지·다이어그램
│
├── scripts/
│   ├── bootstrap.sh                # 개발 환경 초기 세팅
│   ├── gen-openapi-client.sh       # 스펙 → Swift 클라이언트
│   ├── gen-proto.sh                # .proto → Swift/Python 코드
│   └── check-lfs.sh
│
├── .obsidian/                      # Obsidian 볼트 설정 (workspace.json 제외 커밋)
├── .gitattributes                  # Git LFS 규칙
├── .gitignore
├── CLAUDE.md
├── LICENSE
├── Makefile
└── README.md
```

## 7.3 Git LFS

⚠️ **초기에 반드시 설정합니다.** 나중에 걸면 히스토리 재작성이 필요합니다.

```gitattributes
# .gitattributes
*.mlpackage/**  filter=lfs diff=lfs merge=lfs -text
*.mlmodel       filter=lfs diff=lfs merge=lfs -text
*.mlmodelc/**   filter=lfs diff=lfs merge=lfs -text
*.pt            filter=lfs diff=lfs merge=lfs -text
*.pth           filter=lfs diff=lfs merge=lfs -text
*.onnx          filter=lfs diff=lfs merge=lfs -text
*.mov           filter=lfs diff=lfs merge=lfs -text
*.mp4           filter=lfs diff=lfs merge=lfs -text
```

**학습 데이터셋은 LFS에도 넣지 않습니다.** DVC로 외부 스토리지에 두고 포인터만 커밋합니다. 테스트용 샘플 영상(10개 내외, 각 5초)만 LFS로 관리합니다.

## 7.4 브랜치 전략

✅ **확정** — Trunk-based — [D-22](../05-결정/stack/D-22-repository-workflow.md)

```
main                    보호됨. 항상 배포 가능 상태
 ├─ feat/swing-detector
 ├─ fix/overlay-jitter
 └─ chore/ci-cache
```

- 브랜치 수명은 **짧게** (2~3일). 길어지면 쪼갭니다
- `main` 보호 규칙은 **단계적으로 적용**합니다 ([D-22](../05-결정/stack/D-22-repository-workflow.md))
  - 지금: force push 차단, 브랜치 삭제 차단
  - Phase 0 CI 구축 후: PR 필수 + 상태 검사(골든 테스트 포함) 통과 필수
  - ⚠️ 로컬 `gh`가 회사 계정으로 인증되어 있어 **저장소 소유자가 직접 설정**해야 합니다
- Git Flow는 도입하지 않습니다. 1인 개발에 `develop` 브랜치는 순수 오버헤드입니다

### 태그와 릴리즈

컴포넌트별로 독립 버저닝합니다.

```
ios-v1.0.0      → TestFlight 배포 트리거
server-v0.3.0   → 컨테이너 이미지 빌드 + 배포
model-v0.2.0    → 모델 아티팩트 릴리즈
```

## 7.5 커밋 컨벤션

✅ **확정** — gitmoji + Conventional Commits — [D-22](../05-결정/stack/D-22-repository-workflow.md)

```
✨ feat(vision): 스윙 구간 자동 검출 추가
🐛 fix(overlay): 전면 카메라에서 스켈레톤 좌우 반전 수정
♻️ refactor(domain): UseCase 의존성 정리
📝 docs: 비전 파이프라인 문서 추가
✅ test(vision): 골든 테스트 픽스처 추가
⚡️ perf(pose): 분석 입력 다운스케일로 프레임 시간 40% 단축
```

스코프는 모듈명을 사용합니다: `vision`, `capture`, `analysis`, `domain`, `data`, `api`, `worker`, `ml`, `ci`.

## 7.6 PR 규약

| 항목 | 규칙 |
|---|---|
| **Assignee** | 항상 `wnsgur9137` |
| 생성 | 항상 Draft로 만들고, 리뷰 반영 후 Ready 전환 |
| 병합 | merge commit (커밋별 근거를 보존) |
| 정리 | 병합 후 원격·로컬 브랜치 삭제 |

### ⚠️ 인증 — 계정이 두 개다

git과 GitHub API가 **서로 다른 자격증명**을 씁니다.

| 경로 | 자격증명 | 계정 |
|---|---|---|
| `git push` / `pull` | SSH 키 `~/.ssh/id_rsa_wnsgur9137` (Host 별칭 `wnsgur9137`) | 개인 |
| `gh` / GitHub MCP | 환경변수 `WNSGUR9137_GITHUB_TOKEN` | 개인 |
| (주의) `GITHUB_TOKEN` | 셸에 설정된 **회사 계정** 토큰 | ❌ 이 저장소 권한 없음 |

`GITHUB_TOKEN`이 `gh`의 keyring보다 우선하므로, CLI로 PR을 다룰 때는 개인 토큰을 명시해야 합니다.

```bash
export GH_TOKEN="$WNSGUR9137_GITHUB_TOKEN"
unset GITHUB_TOKEN
gh pr create --draft --assignee wnsgur9137 ...
```

`.mcp.json`에 github MCP를 `${WNSGUR9137_GITHUB_TOKEN}`으로 등록해 두었으므로, 세션을 새로 시작하면 MCP 경로로도 동작합니다.

## 7.7 CI 파이프라인

### ios.yml
```yaml
on:
  pull_request:
    paths: ['ios/**', 'contracts/**']
runs-on: macos-15
steps:
  - mise install (Tuist)
  - tuist install && tuist generate
  - swiftlint --strict
  - xcodebuild test (Domain, VisionKit 골든 테스트 포함)
```

**골든 테스트를 CI에 반드시 넣습니다.** 비전 파이프라인은 튜닝이 잦아서, 회귀 검증이 없으면 개선인지 퇴보인지 판단할 수 없습니다.

### server.yml
```yaml
on:
  pull_request:
    paths: ['server/**']
steps:
  - uv sync
  - ruff check && ruff format --check
  - mypy src/
  - pytest --cov
```

### contracts.yml
```yaml
on:
  pull_request:
    paths: ['contracts/**', 'server/src/teniteni/schemas/**']
steps:
  - FastAPI에서 OpenAPI 재생성 → contracts/openapi.yaml과 diff 검증
  - protoc 실행 → Swift/Python 생성 코드가 스키마와 일치하는지 검증
```

[D-11](../05-결정/stack/D-11-networking.md)에서 Moya를 택해 REST 클라이언트는 수동 작성이므로, 계약 검증은 **Protobuf 스키마([D-09](../05-결정/stack/D-09-serialization.md))** 에 집중합니다. OpenAPI에서 DTO만 생성하는 절충안을 도입하면 그 검증도 여기에 추가합니다.

## 7.8 Obsidian 볼트

✅ **확정** — **저장소 루트가 볼트**입니다. 기존 프로젝트(SimpleCare, Lumio, Timespread_IOS)와 동일한 방식입니다.

### 설정

| 설정 | 값 | 이유 |
|---|---|---|
| `useMarkdownLinks` | `true` | GitHub에서도 링크가 동작해야 함 |
| `newLinkFormat` | `relative` | 상대경로로 링크 생성 |
| `alwaysUpdateLinks` | `true` | 파일 이동 시 링크 자동 갱신 |
| `attachmentFolderPath` | `docs/90-첨부` | 첨부가 저장소에 흩어지지 않게 |
| `userIgnoreFilters` | `ios/`, `server/`, `ml/`, ... | 코드 디렉터리의 README를 그래프에서 제외 |
| 템플릿 폴더 | `docs/_templates` | 코어 Templates 플러그인 |

커뮤니티 플러그인은 쓰지 않습니다. 코어 플러그인만으로 충분하며, 특히 **Bases**(1.9+ 코어 DB 기능)로 프론트매터 기반 뷰를 만들 수 있어 Dataview가 필요 없습니다.

### 커밋 정책

`.obsidian/`는 **설정만 커밋하고 개인 작업 상태는 제외**합니다.

```gitignore
.obsidian/workspace.json          # 열린 탭·패널 배치 (개인별)
.obsidian/workspace-mobile.json
.obsidian/cache
.obsidian/plugins/*/data.json
```

`app.json` / `core-plugins.json` / `templates.json` / `graph.json`은 커밋해 링크 형식과 그래프 색상 규칙을 공유합니다.

### 문서 규칙

- 파일명은 **영문**(git·CI 안전), 폴더명은 **한글**(탐색 편의)
- 프론트매터 `aliases`에 한글 표기를 넣어 Obsidian 검색·링크는 한글로 동작
- 링크는 상대경로 마크다운 링크 — Obsidian도 백링크·그래프에 그대로 반영합니다

## 7.9 개발 환경 부트스트랩

```makefile
# Makefile
bootstrap:        ## 최초 1회 실행
	mise install
	git lfs install
	cd ios && tuist install
	cd server && uv sync

generate:         ## Xcode 프로젝트 생성
	cd ios && tuist generate

test-ios:
	cd ios && tuist test

test-server:
	cd server && uv run pytest

openapi:          ## 스펙 → Swift 클라이언트 재생성
	./scripts/gen-openapi-client.sh

up:               ## 로컬 백엔드 기동
	docker compose -f server/docker/compose.yml up -d
```

`mise.toml`로 Tuist / Python / Node 버전을 고정해 환경 차이를 제거합니다.

## 관련 문서

- [iOS 기술 스택](../03-기술스택/IOS-STACK.md)
- [백엔드 기술 스택](../03-기술스택/BACKEND-STACK.md)
- [ADR-0002 모노레포](../05-결정/adr/ADR-0002-monorepo.md)
- [D-22 저장소 워크플로](../05-결정/stack/D-22-repository-workflow.md)

---

[← 문서 허브](../INDEX.md)
