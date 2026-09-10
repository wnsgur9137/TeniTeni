# TeniTeni

테니스 자세 교정 및 볼 궤적 분석 AI 카메라 앱.

> 삼각대에 아이폰을 세워두고 연습하면, 스윙마다 자세를 분석해 무엇을 고쳐야 하는지 알려주고 공이 어디로 갔는지 보여준다.

## 현재 상태

**설계 단계.** 코드는 아직 없습니다. 기술 스택을 확정하는 중입니다.

- **[문서 허브 (INDEX)](docs/INDEX.md)** — 모든 설계 문서의 진입점
- [결정 현황](docs/05-결정/DECISION-LOG.md) — 기술 스택 결정 **0 / 22**

## 개요

| 항목 | 내용 |
|---|---|
| 플랫폼 | iOS (Swift) |
| 추론 구조 | 온디바이스 실시간 + 서버 비동기 정밀 분석 ([ADR-0001](docs/05-결정/adr/ADR-0001-hybrid-inference.md)) |
| 저장소 | 모노레포 ([ADR-0002](docs/05-결정/adr/ADR-0002-monorepo.md)) |
| 자세 평가 | 룰 엔진 우선, 학습형은 유보 ([ADR-0003](docs/05-결정/adr/ADR-0003-rule-based-evaluation.md)) |
| 핵심 기술 | Apple Vision (포즈 추정, 궤적 검출), Core ML (스윙 분류) |

## 핵심 기능

- 실시간 스켈레톤 오버레이 + 공 궤적 트레일
- 스윙 자동 검출 및 유형 분류 (포핸드 / 백핸드 / 서브 / 발리)
- 관절 각도 기반 자세 평가 및 교정 피드백
- 슬로우 모션 리플레이 + 페이즈 분석
- 진척도 추적

## 문서

| 문서 | 내용 |
|---|---|
| [제품 개요](docs/01-제품/PRODUCT-OVERVIEW.md) | 제품 정의, 유스케이스, 범위, 성공 기준 |
| [시스템 아키텍처](docs/02-설계/ARCHITECTURE.md) | 하이브리드 추론, 데이터 흐름, 도메인 모델 |
| [비전 파이프라인](docs/02-설계/VISION-PIPELINE.md) | 포즈, 스윙 검출, 공 궤적, 자세 평가 |
| [스켈레톤 오버레이](docs/02-설계/SKELETON-OVERLAY.md) | 실시간 렌더링 설계 |
| [iOS 기술 스택](docs/03-기술스택/IOS-STACK.md) | 스택 후보, 모듈/파일 구조 |
| [백엔드 기술 스택](docs/03-기술스택/BACKEND-STACK.md) | 백엔드 후보, API 설계 |
| [저장소 구조](docs/03-기술스택/REPOSITORY.md) | 모노레포, 브랜치/CI, Obsidian 볼트 |
| [로드맵과 리스크](docs/04-계획/ROADMAP.md) | 단계별 계획, 리스크 레지스터 |

## Obsidian

이 저장소 루트가 Obsidian 볼트입니다. Obsidian에서 `Open folder as vault`로 이 디렉터리를 열면 됩니다.

- 문서 진입점: `docs/INDEX.md`
- 링크는 상대경로 마크다운 링크라 Obsidian과 GitHub 양쪽에서 동작합니다
- 새 문서는 `docs/_templates/`의 템플릿에서 시작합니다
- `.obsidian/`은 설정만 커밋하고 개인 작업 상태(`workspace.json`)는 제외합니다

## 다음 단계

**Phase 0 — 기술 검증** ([상세](docs/04-계획/ROADMAP.md))

이 앱이 기술적으로 가능한지 판정합니다. 백엔드 코드는 한 줄도 쓰지 않습니다.

게이트: **실제 코트에서 공 궤적 검출률 70% 달성.** 미달 시 접근 방식을 재설계합니다.
