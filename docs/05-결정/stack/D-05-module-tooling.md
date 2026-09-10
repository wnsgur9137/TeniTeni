---
title: "D-05 모듈 빌드 도구"
aliases: ["D-05", "모듈 빌드 도구"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-05
status: decided
group: "A. iOS 기반"
depends_on: []
affects: ["D-22"]
decide_by: "Phase 1 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Tuist 4
---

# D-05. 모듈 빌드 도구

> **상태** ✅ **확정 — Tuist 4** (2026-09-10) · **그룹** A. iOS 기반

## 질문

모듈을 어떤 도구로 분리하고 프로젝트를 생성할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| **Tuist 4** ✅ | 이미 설치됨(4.110.0). 모듈 템플릿화·빌드 설정 일관성 |
| SPM local package만 | 추가 도구 없음. Xcode 네이티브 |
| XcodeGen | 가벼움. 기능은 Tuist보다 적음 |
| 단일 타깃 | Phase 0 한정 |

## 잠정안

**Tuist 4**

## 쟁점

- 1인 개발이면 `project.pbxproj` 충돌이 없어 Tuist의 주 이점이 약해진다
- 다만 모듈 8개 이상 + 빌드 설정 일관성에는 여전히 유리하다
- **Phase 0은 단일 타깃으로 시작하고 Phase 1에서 모듈화하는 안도 유효하다**

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: [D-22](./D-22-repository-workflow.md)

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [저장소 구조](../../03-기술스택/REPOSITORY.md)

## 결정

**Tuist 4를 사용한다.** (로컬에 4.110.0 설치 확인, mise로 버전 고정)

## 근거

- [D-03](./D-03-architecture-pattern.md)에서 TCA를 택해 Feature 모듈마다 Reducer·View·Store가 세트로 생기므로, **모듈 템플릿화의 가치가 커졌다**
- Domain / Data / VisionKit / Features / DesignSystem 등 모듈이 10개 내외로 늘어난다. 빌드 설정을 한 곳에서 관리해야 한다
- TCA는 매크로로 빌드 시간이 늘어나므로, 모듈 분리로 증분 빌드 범위를 좁히는 것이 실익이 된다

**Phase 0 예외**: 기술 검증 단계에서는 단일 타깃으로 시작하고, Phase 1에서 Tuist 모듈 구조로 재편한다. 검증 전에 모듈을 나누는 것은 이르다.

---

[← 결정 현황](../DECISION-LOG.md)
