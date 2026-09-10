---
title: "D-22 저장소 구조 및 워크플로"
aliases: ["D-22", "저장소 구조 및 워크플로"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-22
status: open
group: "E. 저장소 / 프로세스"
depends_on: ["D-05"]
affects: []
decide_by: "첫 커밋 전"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-22. 저장소 구조 및 워크플로

> **상태** ⬜ 미결 · **그룹** E. 저장소 / 프로세스 · **확정 시점** 첫 커밋 전

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

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
