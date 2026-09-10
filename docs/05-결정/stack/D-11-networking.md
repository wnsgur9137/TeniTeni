---
title: "D-11 네트워크 계층"
aliases: ["D-11", "네트워크 계층"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-11
status: open
group: "C. iOS 부가 스택"
depends_on: ["D-14"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 
decision: 
---

# D-11. 네트워크 계층

> **상태** ⬜ 미결 · **그룹** C. iOS 부가 스택 · **확정 시점** Phase 2

## 질문

서버 통신 계층을 무엇으로 구현할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| URLSession + swift-openapi-generator | 계약 자동 검증. Apple 공식 |
| Alamofire | 익숙함. 이 프로젝트엔 기능 과잉 |
| Moya | 추상화 레이어. 의존성 추가 |

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

> 아직 결정되지 않았습니다.

## 근거

---

[← 결정 현황](../DECISION-LOG.md)
