---
title: "D-18 오브젝트 스토리지"
aliases: ["D-18", "오브젝트 스토리지"]
tags:
  - 문서유형/결정
  - 영역/인프라
id: D-18
status: decided
group: "D. 백엔드"
depends_on: ["D-15"]
affects: []
decide_by: "Phase 2"
created: 2026-09-10
updated: 2026-09-10
decided_on: 2026-09-10
decision: Cloudflare R2
---

# D-18. 오브젝트 스토리지

> **상태** ✅ **확정 — Cloudflare R2** (2026-09-10) · **그룹** D. 백엔드

## 질문

영상 파일을 어디에 저장할 것인가?

## 후보

| 후보 | 메모 |
|---|---|
| Cloudflare R2 | **egress 무료**. 영상 서비스에 결정적 |
| AWS S3 | 생태계 최강. egress 비쌈 |
| Supabase Storage | BaaS 채택 시 통합 편의 |

## 잠정안

**Cloudflare R2**

## 쟁점

- 영상 다운로드가 반복되므로 egress 비용 차이가 크게 벌어진다
- presigned URL로 앱이 직접 업로드해 API 서버를 우회한다

## 의존 관계

- **선행 결정**: [D-15](./D-15-baas-vs-selfhosted.md)
- **영향받는 결정**: 없음

## 영향받는 문서

- [백엔드 기술 스택](../../03-기술스택/BACKEND-STACK.md)

## 결정

**Cloudflare R2.** S3 호환 API를 사용하므로 `boto3`를 그대로 쓴다.

## 근거

- **egress 무료.** 리플레이·레퍼런스 비교로 같은 영상을 반복 다운로드하는 패턴이라 S3 대비 비용 차이가 크게 벌어진다
- S3 호환이라 SDK·presigned URL 방식이 동일하다. 나중에 S3로 이전해도 코드 변경이 거의 없다
- [D-15](./D-15-baas-vs-selfhosted.md) 자체 구축과 무관하게 스토리지만 위임할 수 있다

## 저장 대상

| 경로 | 내용 |
|---|---|
| `clips/{userId}/{clipId}.mov` | 스윙 구간 영상 (HEVC) |
| `poses/{clipId}.pb.gz` | 포즈 시계열 Protobuf ([D-09](./D-09-serialization.md)) |
| `references/{referenceId}.mov` | 프로 레퍼런스 (Phase 3) |

## 업로드 경로

영상은 **API 서버를 경유하지 않는다.**

```
1. 앱 → POST /v1/clips            → clipId + presigned PUT URL
2. 앱 → PUT <presigned URL>       → R2에 직접 업로드
3. 앱 → POST /v1/clips/{id}/complete → 분석 큐 등록 (202)
```

Wi-Fi 연결 시에만, `URLSession` background configuration으로 전송한다.

## 주의

**사용자 삭제 요청 시 원본과 파생 데이터를 모두 지운다** ([02. 시스템 아키텍처](../../02-설계/ARCHITECTURE.md) 2.6절 프라이버시 원칙). 영상·포즈 파일·DB 레코드가 각각 다른 곳에 있으므로 삭제 경로를 명시적으로 구현해야 한다.

---

[← 결정 현황](../DECISION-LOG.md)
