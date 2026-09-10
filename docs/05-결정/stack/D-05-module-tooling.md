---
title: "D-05 모듈 빌드 도구"
aliases: ["D-05", "모듈 빌드 도구"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-05
status: open
group: "A. iOS 기반"
depends_on: []
affects: ["D-22"]
decide_by: "Phase 1 이전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-05. 모듈 빌드 도구

> **상태** ⬜ 미결 · **그룹** A. iOS 기반 · **확정 시점** Phase 1 이전

## 질문

모듈을 어떤 도구로 분리하고 프로젝트를 생성할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Tuist 4 | 이미 설치됨. 모듈 템플릿화·빌드 설정 일관성 |
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

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
