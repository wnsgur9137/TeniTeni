---
title: "D-13 크래시 리포팅 / 분석"
aliases: ["D-13", "크래시 리포팅 / 분석"]
tags:
  - 문서유형/결정
  - 영역/iOS
id: D-13
status: decided
group: "C. iOS 부가 스택"
depends_on: []
affects: []
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Firebase Crashlytics
---

# D-13. 크래시 리포팅 / 분석

> **상태** ✅ **확정 — Firebase Crashlytics** (2026-09-10) · **그룹** C. iOS 부가 스택

## 질문

크래시와 사용 지표를 무엇으로 수집할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Firebase Crashlytics | 업계 표준. SDK 무겁고 프라이버시 라벨 증가 |
| Sentry | 크래시+성능. 셀프호스팅 가능 |
| TelemetryDeck | 프라이버시 친화적. 크래시 리포팅 약함 |
| 없음 | Phase 1까지 미도입 |

## 잠정안

**미정**

## 쟁점

- 영상·얼굴을 다루는 앱이라 **프라이버시 라벨이 심사와 신뢰에 직결**된다
- Firebase는 SDK가 무겁고 수집 항목이 늘어난다
- 발열·프레임 드롭 추적에는 성능 모니터링이 실제로 유용하다

## 의존 관계

- **선행 결정**: 없음
- **영향받는 결정**: 없음

## 영향받는 문서

- [iOS 기술 스택](../../03-기술스택/IOS-STACK.md)

## 결정

**Firebase Crashlytics.** Analytics는 최소 범위로 함께 도입한다.

## 근거

- 무료 무제한이라 이벤트 한도를 신경 쓰지 않는다
- 기존 프로젝트에서 써온 도구라 대시보드·알림 설정 경험이 그대로 쓰인다
- 자료가 가장 많아 문제 해결이 빠르다

## 비용과 대응

**프라이버시 라벨이 길어진다.** 얼굴 영상을 다루는 앱이라 이 부분이 심사와 사용자 신뢰에 직결된다.

→ 대응:
- **Analytics 수집 항목을 최소로 제한한다.** 화면 전환·기능 사용 여부 수준까지만. 스윙 데이터·영상 메타는 보내지 않는다
- `AnalyticsCollectionEnabled`를 설정에서 끌 수 있게 한다
- 개인정보 처리방침에 수집 항목을 명시한다 (Phase 2 이전, R-8)

**성능 모니터링이 약하다.** 이 앱의 핵심 리스크는 발열·프레임 드롭·배터리(R-5, R-7)인데 Crashlytics만으로는 추적이 어렵다.

→ 대응: **자체 성능 지표를 수집한다.** `ProcessInfo.thermalState`, 프레임 처리 시간, 드롭률을 세션 요약에 기록하고 Analytics 커스텀 이벤트로 집계한다. 부족하면 Phase 2에서 Firebase Performance Monitoring 추가를 검토한다.

---

[← 결정 현황](../DECISION-LOG.md)
