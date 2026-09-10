---
title: "D-09 포즈 시계열 직렬화 포맷"
aliases: ["D-09", "포즈 시계열 직렬화 포맷"]
tags:
  - 문서유형/결정
  - 영역/비전
id: D-09
status: decided
group: "B. 비전 파이프라인"
depends_on: ["D-06", "D-08"]
affects: []
decide_by: "Phase 1"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Protobuf (swift-protobuf)
---

# D-09. 포즈 시계열 직렬화 포맷

> **상태** ✅ **확정 — Protobuf** (2026-09-10) · **그룹** B. 비전 파이프라인

## 질문

프레임별 관절 데이터를 어떤 포맷으로 파일에 저장할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Protobuf | 압축률·속도 우수. 스키마 관리 필요 |
| FlatBuffers | 제로카피 읽기. 생태계 작음 |
| MessagePack | 간편. 스키마 없음 |
| JSON + gzip | 디버깅 쉬움. 크기·속도 열위 |

## 잠정안

**Protobuf**

## 쟁점

- 스윙 하나에 **좌표 5,700개**(60fps × 19관절 × 5초). DB 행으로 넣으면 폭발한다
- 서버와 포맷을 공유해야 하므로 Swift/Python 양쪽 지원이 필수다
- 디버깅 편의를 위해 개발 빌드에서는 JSON으로 덤프하는 옵션을 둘 수 있다

## 의존 관계

- **선행 결정**: [D-06](./D-06-pose-engine.md), [D-08](./D-08-local-db.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [시스템 아키텍처](../../02-설계/ARCHITECTURE.md)

## 결정

**Protobuf** (`swift-protobuf`). 스키마는 `contracts/`에 두고 Swift·Python 양쪽에서 생성한다.

## 근거

- 스윙 하나에 좌표 5,700개(60fps × 19관절 × 5초). 크기와 파싱 속도가 실제로 영향을 준다
- **Swift와 Python이 같은 스키마를 공유**한다. Phase 2 서버 연동에서 파서를 따로 작성하지 않는다
- [D-11](./D-11-networking.md)의 OpenAPI와 같은 원칙 — 계약을 한 곳에 두고 양쪽에서 생성한다

`HumanBodyPoseObservation`이 `Codable`을 준수하지만, 그 형태에 묶이면 서버 쪽 파서를 직접 작성해야 하고 Apple 타입 변경에 영향을 받는다. **자체 스키마를 두어 도메인 표현을 통제한다.**

## 스키마 배치

```
contracts/
├── openapi.yaml           # REST API (D-11)
└── proto/
    ├── pose.proto         # PoseFrame, Joint
    ├── trajectory.proto   # TrajectoryPoint
    └── swing.proto        # Swing, SwingMetrics
```

생성 산출물은 커밋하지 않고 빌드 시 생성한다(`scripts/gen-proto.sh`).

## 비용

- 스키마 관리와 변환 레이어가 Phase 1부터 생긴다. Phase 1까지는 로컬 전용이라 당장의 이득은 크기·속도뿐이다
- 디버깅 시 사람이 읽을 수 없다 → **개발 빌드에서 JSON 덤프 옵션**을 함께 제공한다

---

[← 결정 현황](../DECISION-LOG.md)
