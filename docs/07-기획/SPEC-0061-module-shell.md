---
title: "SPEC-0061 모듈 재편 + 앱 셸"
aliases: ["SPEC-0061", "1-A", "앱 셸"]
tags:
  - 문서유형/기획
  - 영역/코어
issue: 61
type: "✨Feature"
area: "🧩Core"
created: 2026-09-16
updated: 2026-09-16
status: active
---

# SPEC-0061. 모듈 재편 + 앱 셸

> 이슈 [#61](https://github.com/wnsgur9137/TeniTeni/issues/61) · 마일스톤 `1-A 모듈 재편`

## 배경

[작업 순서 9.4](../04-계획/WORK-PLAN.md)의 1-A입니다. [#55](https://github.com/wnsgur9137/TeniTeni/issues/55)에서 **게이트 앞으로 당겼습니다** — 궤적 검출 성패와 무관하고 카메라도 필요 없습니다.

현재는 0-A 단일 타깃이고 진입점이 화면을 직접 띄웁니다.

```swift
@main
struct TeniTeniApp: App {
    var body: some Scene {
        WindowGroup { CaptureView() }
    }
}
```

모듈 구조와 의존성 방향은 [9.6](../04-계획/WORK-PLAN.md)이, 계층 규칙은 [D-03](../05-결정/stack/D-03-architecture-pattern.md)이, 도구는 [D-05](../05-결정/stack/D-05-module-tooling.md)가 이미 정했습니다. **재론하지 않습니다.**

## 범위

### 만들 것

- `Domain` · `Data` · `Presentation` · `Application` · `DesignSystem` 모듈
- `Application` 코디네이터 — 진입점이 화면을 직접 띄우지 않게
- **탭바 3개** 골격 (촬영 / 보관함 / 진척도)
- **화면 방향 정리** — 촬영만 가로 고정
- `Tokens.swift`를 `DesignSystem`으로 이동

### 만들지 않을 것

- **진입 화면 내용** — 온보딩·주 사용 손·홈·설정은 **1-A′**. 이 작업은 **골격**입니다
- **`Network` 모듈** — 9.6이 2-C로 정했습니다. 그전에 만들면 빈 모듈입니다
- **`Core` 모듈** — 9.6이 0-D로 정했고, 아직 공용 유틸이 없습니다
- **`Domain` 엔티티** — Session·Clip·Swing은 1-B가 확정합니다
- **촬영 기능 변경** — `CaptureView`는 **옮기기만** 합니다

## 구현 선택지

### 1. TCA를 1-A에서 도입하는가

[D-03](../05-결정/stack/D-03-architecture-pattern.md)이 `Presentation`에 TCA를 쓰기로 정했지만 **언제 넣을지는 정하지 않았습니다.** 현재 앱·TeniVision은 **외부 의존성 0**입니다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. 지금 넣고 Root Reducer만** | 코디네이터 구조가 처음부터 정본. 1-A′는 자식 Feature만 붙인다 | 화면이 없어 Reducer가 거의 빈다 |
| B. 1-A′로 미룬다 | 쓸 곳이 생길 때 넣는다 — 9.6의 "필요할 때 만든다" | **1-A의 코디네이터를 1-A′에서 다시 짠다.** 완료 기준이 무의미해진다 |
| C. TCA를 안 쓴다 | 가장 단순 | D-03을 뒤집는 것. 근거 없이 되돌릴 수 없다 |

**채택: A.** B의 문제가 결정적입니다 — **코디네이터는 1-A의 산출물**인데 그것을 다음 단계에서 다시 짜면 1-A가 무엇을 완료했는지 말할 수 없습니다.

빈 Reducer 걱정은 과장입니다. Root는 **"온보딩을 마쳤는가"로 온보딩과 탭바를 가르는 실제 분기**를 갖습니다. 1-A′는 그 분기의 양쪽을 채웁니다.

> `Network`를 안 만드는 것과 다른 판단인 이유: `Network`는 **부를 곳이 Phase 2까지 없지만**, 코디네이터는 **지금 당장 필요합니다.**

### 2. 탭 루트를 어떻게 두는가

1-A′와 1-E가 채울 때까지 탭 내용이 없습니다.

| 선택지 | 내용 |
|---|---|
| A. 탭마다 빈 `Text("준비 중")` | 가장 단순. 무엇이 올지 모른다 |
| **B. 탭마다 Feature 모듈 자리를 만들고 placeholder View** | 1-A′·1-E가 **파일을 바꾸지 않고 내용만** 채운다 |
| C. 촬영 탭만 진짜(`CaptureView`), 나머지 빈 화면 | 회귀 위험이 가장 낮다 |

**채택: B + C 혼합.** 촬영 탭은 **기존 `CaptureView`를 그대로** 붙여 0-A 회귀를 막고, 나머지 둘은 placeholder를 둡니다.

### 3. 방향 제어를 어디서 하는가

`Info.plist`가 앱 전체를 가로로 묶고 있습니다. 세로 화면 12종을 띄우려면 풀어야 하는데, 촬영은 가로여야 합니다.

| 선택지 | 장점 | 단점 |
|---|---|---|
| **A. `Info.plist`를 전 방향 허용 + 촬영 화면만 잠금** | 화면이 자기 방향을 안다 | 화면마다 잠금 코드가 필요 |
| B. 코디네이터가 방향을 관리 | 한 곳에서 제어 | 화면과 방향이 멀어져 추적이 어렵다 |

**채택: A.** iOS 26의 `UIViewController.supportedInterfaceOrientations` 계열은 화면 단위 선언이 자연스럽고, **"이 화면은 가로다"가 그 화면 코드에 적혀 있는 편**이 나중에 읽기 쉽습니다.

## 완료 기준

- [ ] `ios/Projects/`에 `Domain`·`Data`·`Presentation`·`Application`·`DesignSystem` 5개가 생기고 `tuist generate` 통과
- [ ] **`Domain`이 Foundation 외에 아무것도 import하지 않는다** — 매니페스트의 `dependencies`가 비어 있다
- [ ] 의존성 방향이 9.6과 일치 (`Presentation → Domain`, `Data → Domain`, `Network` 없음)
- [ ] `TeniTeniApp`이 **코디네이터를 띄운다** — `CaptureView()`를 직접 띄우지 않는다
- [ ] 탭바 3개가 뜨고 전환된다
- [ ] **촬영 탭이 기존과 같이 동작한다** (포맷 인스펙터 포함)
- [ ] **세로 화면이 세로로, 촬영이 가로로** 뜬다
- [ ] `Tokens.swift`가 `DesignSystem` 모듈로 이동 (`git mv`, 내용 불변)
- [ ] **`verify-docs.sh`의 토큰 검사가 새 경로에서 살아 있다**
- [ ] `scripts/verify-ios.sh` 통과, 경고 0

## 검증 방법

| 항목 | 방법 |
|---|---|
| 게이트 | `scripts/verify-ios.sh` (`CLEAN_BUILD=1`로 한 번 더) |
| 의존성 방향 | `Domain` 매니페스트에 `dependencies` 없음을 눈으로. 있으면 빌드가 아니라 **규칙 위반** |
| 토큰 이동 | `verify-docs.sh` 통과 + **일부러 색을 어긋내 검사가 살아 있는지 확인** |
| 방향 | 시뮬레이터에서 탭 전환하며 회전 |
| 회귀 | 촬영·포맷 인스펙터가 이전과 동일하게 동작 |

**토큰 검사의 변이 시험이 중요합니다.** 스크립트가 경로를 하드코딩하고, 파일이 없으면 `"Tokens.swift 없음 — 건너뜁니다"`로 **조용히 꺼집니다.** 경로를 고쳤다고 믿고 넘어가면 이후 목업과 구현이 갈라져도 게이트가 통과합니다.

## 영향받는 문서

- [작업 순서 9.6](../04-계획/WORK-PLAN.md) — 도입 순서 표의 1-A 행
- [D-03](../05-결정/stack/D-03-architecture-pattern.md) — TCA 도입 시점을 이 기획서가 정함
- `scripts/verify-docs.sh` — `Tokens.swift` 경로

## 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| **토큰 검사가 조용히 꺼진다** | 목업과 구현이 갈라져도 게이트 통과 | 경로를 고치고 **변이 시험으로 살아 있는지 확인**. 완료 기준에 넣었다 |
| Tuist 재편이 빌드를 깬다 | 되돌리기 번거로움 | 모듈을 한 번에 만들지 않고 **단계별로 게이트를 돌린다** |
| 방향 해제가 촬영을 깬다 | 0-A 회귀 | 촬영만 잠금. 시뮬레이터에서 회전 확인 |
| TCA 매크로로 빌드가 느려진다 | 반복 저하 | [D-05](../05-결정/stack/D-05-module-tooling.md)가 이미 예상한 비용. 모듈 분리로 증분 범위를 좁히는 것이 상쇄책이다 |
| `Domain`·`Data`가 빈 모듈 | 9.6이 경고한 상황 | **이번엔 비어도 된다** — 1-A′와 1-B가 곧 채운다. `Network`와 다른 점은 **채울 시점이 정해져 있다**는 것 |

## 미수행으로 남길 것

- **실기기 검증** — 시뮬레이터로 방향·탭 전환은 보지만 6m 가독성은 실기기가 필요합니다
- **진입 화면 내용** — 1-A′
- **`Domain` 엔티티 확정** — 1-B
- **`TestStore` 기반 Reducer 테스트** — Reducer가 실제 분기를 갖는 1-A′부터 의미가 있습니다

## 관련 문서

- [작업 순서 9.4·9.6](../04-계획/WORK-PLAN.md)
- [D-03 아키텍처 패턴](../05-결정/stack/D-03-architecture-pattern.md) · [D-05 모듈 도구](../05-결정/stack/D-05-module-tooling.md)
- [IA-FLOW 10.2](../06-디자인/IA-FLOW.md) — 탭바
- [SPEC-0005 TeniVision 모듈 분리](SPEC-0005-tenivision-module.md) — 첫 모듈 분리의 선례

---

[← 문서 허브](../INDEX.md)
