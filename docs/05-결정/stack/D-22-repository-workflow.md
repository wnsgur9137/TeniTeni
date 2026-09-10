---
title: "D-22 저장소 구조 및 워크플로"
aliases: ["D-22", "저장소 구조 및 워크플로"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-22
status: decided
group: "E. 저장소 / 프로세스"
depends_on: ["D-05"]
affects: []
decide_by: "첫 커밋 전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: 모노레포 + trunk-based, 브랜치 보호는 단계적 적용
---

# D-22. 저장소 구조 및 워크플로

> **상태** ✅ **확정** (2026-09-10) · **그룹** E. 저장소 / 프로세스

## 질문

저장소 구조와 개발 워크플로를 어떻게 확정할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| 모노레포 + trunk-based | 단일 저장소. 계약 변경 원자성 |
| 멀티레포 | 컴포넌트 독립. 1인 개발엔 오버헤드 |

## 잠정안

**모노레포 + trunk-based + gitmoji/Conventional Commits**

## 쟁점

- **Git LFS는 첫 커밋 전에 설정해야 한다.** 나중에 걸면 히스토리 재작성이 필요하다
- CI는 `paths` 필터로 변경 영역만 실행한다
- 컴포넌트별 태그 프리픽스(`ios-v*`, `server-v*`)로 릴리즈를 분리한다

## 의존 관계

- **선행 결정**: [D-05](./D-05-module-tooling.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [저장소 구조](../../03-기술스택/REPOSITORY.md)
- [ADR-0002 모노레포](../../05-결정/adr/ADR-0002-monorepo.md)

## 결정

**모노레포 + trunk-based + gitmoji/Conventional Commits.** 브랜치 보호는 **단계적으로 적용**한다.

## 적용 완료 (2026-09-10)

| 항목 | 상태 |
|---|---|
| 모노레포 `wnsgur9137/TeniTeni` | ✅ [ADR-0002](../adr/ADR-0002-monorepo.md) |
| Git LFS + `.gitattributes` | ✅ 첫 커밋 전에 설정 |
| `core.precomposeunicode` | ✅ 한글 경로 NFD 대응 |
| 커밋 컨벤션 | ✅ gitmoji + Conventional Commits |
| 기본 브랜치 `main` | ✅ |

## 브랜치 보호 — 단계적 적용

**지금 (CI 없음)**

CI가 없는 상태에서 PR을 필수화하면 검사할 것이 없는데 마찰만 생긴다. 히스토리 훼손 방지만 건다.

- Force push 차단
- 브랜치 삭제 차단

**Phase 0에서 CI 구축 후**

`ios.yml`이 동작하기 시작하면 강제한다.

- PR 필수 (직접 푸시 차단)
- 상태 검사 통과 필수 (`ios`, `server`, `contracts`)
- **골든 테스트를 필수 검사에 포함** — 비전 파이프라인은 튜닝이 잦아 회귀 검증이 없으면 개선인지 퇴보인지 알 수 없다

## ⚠️ 수동 조치 필요

로컬 `gh` CLI가 **회사 계정(`JunHyeok0206`)으로 인증**되어 있어 이 저장소에 admin 권한이 없다. 브랜치 보호는 저장소 소유자(`wnsgur9137`)가 직접 설정해야 한다.

```
GitHub → Settings → Branches → Add branch ruleset
  Target: main
  ☑ Block force pushes
  ☑ Restrict deletions
```

또는 `gh auth login`으로 `wnsgur9137` 계정을 추가한 뒤:

```bash
gh api -X PUT repos/wnsgur9137/TeniTeni/branches/main/protection \
  -f required_status_checks=null -F enforce_admins=false \
  -f required_pull_request_reviews=null -f restrictions=null \
  -F allow_force_pushes=false -F allow_deletions=false
```

> 참고: git 푸시는 SSH 키(`git@wnsgur9137`)를 쓰므로 정상 동작한다. `gh` CLI 계정과는 별개다.

---

[← 결정 현황](../DECISION-LOG.md)
