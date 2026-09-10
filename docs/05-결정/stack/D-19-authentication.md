---
title: "D-19 인증"
aliases: ["D-19", "인증"]
tags:
  - 문서유형/결정
  - 영역/백엔드
id: D-19
status: decided
group: "D. 백엔드"
depends_on: ["D-15"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Sign in with Apple + 자체 JWT
---

# D-19. 인증

> **상태** ✅ **확정 — Sign in with Apple + 자체 JWT** (2026-09-10) · **그룹** D. 백엔드

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

**Sign in with Apple + 자체 JWT.** 소셜 로그인은 Apple 하나만 지원한다.

## 근거

- iOS 단독 앱이라 Apple 로그인만으로 충분하다. 사용자는 버튼 한 번으로 가입한다
- [D-15](./D-15-baas-vs-selfhosted.md) 자체 구축과 일관된다. 서버가 외부 토큰 검증에 의존하지 않는다
- Firebase Auth는 D-13에서 이미 Firebase를 넣으므로 비용이 작지만, **인증까지 종속되면 이탈 비용이 커진다.** 크래시 리포팅은 교체가 쉽지만 인증은 그렇지 않다

## 흐름

```
1. 앱  → ASAuthorizationAppleIDProvider로 identityToken 획득
2. 앱  → POST /v1/auth/apple { identityToken }
3. 서버 → Apple 공개키(JWKS)로 토큰 검증, sub 추출
4. 서버 → users 조회/생성 → access(단기) + refresh(장기) JWT 발급
5. 앱  → Keychain에 저장, Moya 플러그인이 헤더에 주입
```

## 주의

- **Apple은 이메일을 첫 로그인에만 준다.** 재로그인 시 오지 않으므로 최초 응답에서 반드시 저장한다
- **이메일 가리기(Private Relay)** 사용자가 있다. 이메일을 식별자로 쓰지 말고 `sub`를 기준으로 한다
- **계정 삭제 시 Apple 연동 해제**(revoke token)가 App Store 심사 요구사항이다
- refresh 토큰 회전과 재사용 감지를 구현한다

---

[← 결정 현황](../DECISION-LOG.md)
