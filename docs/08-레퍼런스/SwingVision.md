---
title: "SwingVision"
aliases: ["SwingVision"]
tags:
  - 문서유형/레퍼런스
  - 영역/제품
researched: 2026-09-11
created: 2026-09-10
updated: 2026-09-11
status: active
---

# SwingVision

> 가장 직접적 경쟁. iOS 네이티브, 온디바이스 분석, 코트 인식·인아웃 판정

## 2026-09-11 — 촬영 중 화면 가독성

이슈 [#22](https://github.com/wnsgur9137/TeniTeni/issues/22) 착수 전 조사. **촬영 중 UX로 범위를 좁혔습니다.** 지표 정의·기능 범위는 해당 작업에서 채웁니다.

### 사용자 불만 — 코트에서 화면을 볼 수 없다

반복되는 지적입니다.

> 펜스 마운트의 문제는 **카메라가 제대로 잡혔는지 확인할 수 없다**는 것이다 — iPad나 Apple Watch로 화면 미러링을 하지 않는 한.

확인하려고 장비를 더 들고 나가야 합니다. 클램프가 화면을 가려 조작이 안 된다는 지적도 있습니다.

**이것이 [IA-FLOW 10.5](../06-디자인/IA-FLOW.md)의 6m 가독성 설계가 겨냥하는 지점입니다.** 우리는 폰이 6m 떨어져 있다는 전제에서 출발해 "세밀한 정보를 버리고 세 가지만 남긴다"로 갔습니다. 같은 문제를 다른 방향에서 푼 것입니다 — 그들은 보조 기기로, 우리는 멀리서도 읽히는 화면으로.

가설이 독립적으로 확인됐습니다. **다만 그들이 이 문제를 방치했다는 뜻은 아닙니다** — 리뷰는 마운트·클램프 하드웨어 이야기가 대부분이고, 앱 화면 자체를 어떻게 만들었는지는 스토어 페이지로 알 수 없습니다.

### 거치 방식이 다릅니다

| | SwingVision | TeniTeni |
|---|---|---|
| 권장 거치 | **펜스 상단 마운트** (삼각대보다 정확) | 삼각대, 높이 1.1 m |
| 목적 | 코트 전체 + 인아웃 판정 | **측면 포즈 + 공 궤적** |

목적이 다르므로 그대로 가져올 수 없습니다. 코트를 넓게 담으려면 높고 멀어야 하지만, 우리는 관절이 보여야 하므로 가깝고 낮아야 합니다 ([촬영 프로토콜 5.1](../02-설계/CAPTURE-PROTOCOL.md)).

### 한계

스토어 페이지와 리뷰로 얻은 것입니다. **촬영 중 화면이 실제로 어떻게 생겼는지는 확인하지 못했습니다.** 시각적 모방을 하지 않으므로 그 이상 파지 않았습니다.

## 남은 조사 항목

- **지표 정의** — 무엇을 측정하고 어떻게 이름 붙이는가
- **기능 범위** — v1에 무엇을 넣고 무엇을 뺐는가
- **우리와의 차이** — 리플레이·피드백 영역

## 출처

- [App Store 리뷰](https://apps.apple.com/us/app/swingvision-tennis-pickleball/id989461317)
- [Tennisnerd 리뷰·인터뷰](https://www.tennisnerd.net/tennis-tools/swingvision-review-and-interview/25702)
- [Tennis.com 기사](https://www.tennis.com/news/articles/swingvision-delivers-pro-level-insights-for-recreational-players)

## 관련 문서

- [레퍼런스 허브](INDEX.md)

---

[← 문서 허브](../INDEX.md)
