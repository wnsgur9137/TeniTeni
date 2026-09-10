---
title: "D-11 네트워크 계층"
aliases: ["D-11", "네트워크 계층"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-11
status: decided
group: "C. iOS 부가 스택"
depends_on: ["D-14"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Moya
---

# D-11. 네트워크 계층

> **상태** ✅ **확정 — Moya** (2026-09-10) · **그룹** C. iOS 부가 스택

## 질문

서버 통신 계층을 무엇으로 구현할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| **Moya** ✅ | `TargetType` enum으로 엔드포인트 일괄 정리. Alamofire 위에 얹힘 |
| URLSession + swift-openapi-generator | 계약을 컴파일 타임 검증. 생성 코드 제어권 일부 상실 |
| URLSession 직접 | 의존성 0. 엔드포인트마다 수동 작성 |
| Alamofire | Moya 없이 단독. 라우팅 구조를 직접 설계해야 함 |

## 잠정안

**URLSession + swift-openapi-generator**

## 쟁점

- OpenAPI에서 클라이언트를 생성하면 **계약 불일치를 컴파일 타임에** 잡는다
- 대신 생성 코드의 제어권을 일부 잃는다
- 서버가 OpenAPI를 내는지에 달려 있다

## 의존 관계

- **선행 결정**: [D-14](./D-14-backend-framework.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)
- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

**Moya.** 엔드포인트를 `TargetType` enum으로 선언한다.

## 근거

- 엔드포인트가 한 파일에 열거되어 API 표면이 한눈에 보인다
- 기존 프로젝트에서 써온 방식이라 라우팅·플러그인 패턴을 그대로 재사용한다
- 스텁 응답이 내장되어 있어 서버 없이 Phase 1에서 Data 계층 테스트가 가능하다

## 비용과 대응

**의존성이 2개가 된다.** Moya는 Alamofire 위에 얹힌다.

**계약 검증 이점을 잃는다.** [D-09](./D-09-serialization.md)에서 Protobuf 스키마 공유를 택한 원칙 — *계약을 한 곳에 두고 양쪽에서 생성* — 이 REST API에는 적용되지 않는다.

→ **절충안**: `contracts/openapi.yaml`에서 **DTO만 생성**하고, 전송은 Moya `TargetType`이 담당한다. 스펙 변경이 모델 레벨에서는 컴파일 타임에 잡힌다. Phase 2 착수 시 도입 여부를 판단한다.

⬜ **Phase 2에서 확인할 것**: Moya / Alamofire의 Swift 6 strict concurrency 대응 상태. `Sendable` 관련 경고가 많으면 `@preconcurrency import` 또는 얇은 래퍼로 격리한다.

---

[← 결정 현황](../DECISION-LOG.md)
