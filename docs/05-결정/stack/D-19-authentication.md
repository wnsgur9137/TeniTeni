---
title: "D-19 인증"
aliases: ["D-19", "인증"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-19
status: open
group: "D. 백엔드"
depends_on: ["D-15"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-19. 인증

> **상태** ⬜ 미결 · **그룹** D. 백엔드 · **확정 시점** Phase 2

## 질문

사용자 인증을 어떻게 구현할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Sign in with Apple + 자체 JWT | 의존성 최소. 구현량 있음 |
| Firebase Auth | 빠름. Firebase 종속 |
| Supabase Auth | BaaS 채택 시 자연스러움 |

## 잠정안

**미정**

## 쟁점

- iOS 단독 앱이므로 Sign in with Apple만으로 충분할 수 있다
- App Store 심사상 소셜 로그인을 넣으면 Apple 로그인이 필수다
- D-15 결정에 종속된다

## 의존 관계

- **선행 결정**: [D-15](./D-15-baas-vs-selfhosted.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
