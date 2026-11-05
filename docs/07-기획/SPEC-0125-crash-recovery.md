---
title: "SPEC-0125 강제 종료된 세션을 복구한다"
aliases: ["SPEC-0125", "강제 종료 복구", "CrashRecovery"]
tags:
  - 문서유형/기획
  - 영역/UI
issue: 125
type: feature
area: ui
created: 2026-11-05
updated: 2026-11-05
status: active
---

# SPEC-0125. 강제 종료된 세션을 복구한다

> 이슈 [#125](https://github.com/wnsgur9137/TeniTeni/issues/125)

## 배경

[IA-FLOW 10.6](../06-디자인/IA-FLOW.md)이 정했습니다 — **앱 강제 종료 → 다음 실행 → "지난 세션이 끝나지 않았습니다" → 복구 / 폐기.**

**구현이 없습니다.** 다음 실행에서 아무 일도 일어나지 않습니다.

코드는 이 상황을 알고 있습니다. `SwingPipeline`에 두 번 적혀 있습니다.

> 저장소가 없으면 `nil`이다. 그래도 **클립 파일은 쓴다** — 디스크에 남은 `.mov`는 나중에 복구할 수 있는 자산이고, 안 만들면 그조차 없다.

즉 **복구 가능한 상태로 남기는 것까지는 했고, 복구하는 쪽이 없습니다.** 레퍼런스 조사에서 반복된 불만이 정확히 이것입니다 — TennisCut은 촬영 크래시로 녹화가 통째로 사라졌고, 개발사 답변이 "다음 실행에서 중단된 것을 복구한다"였습니다([SwingVision 레퍼런스](../08-레퍼런스/SwingVision.md)).

### ⚠️ 이슈 본문의 첫 할 일은 지금 구조에서 작동하지 않습니다

이슈가 적은 것: `"끝나지 않은 세션을 판정한다 — endedAt == nil인 레코드"`.

**그런 레코드는 생기지 않습니다.** 세션을 저장하는 호출은 코드 전체에서 하나뿐이고(`SessionBuilder.swift:90`), 그것을 부르는 곳은 `finish(at:)`입니다.

```swift
public func finish(at endedAt: Date) async throws -> Session {
    let session = Session(id: id, startedAt: startedAt, endedAt: endedAt, ...)
    try await repository.save(session)   // ← 저장은 여기서 단 한 번
    return session
}
```

강제 종료되면 **레코드가 0건**이고 `.mov`만 남습니다. 이슈 **제목**("지금은 고아 클립만 남는다")이 맞고 **할 일**이 제목과 모순입니다.

그래서 이 기획서는 갈림길을 하나 더 다룹니다 — **세션 레코드를 언제 저장하는가.** 그것이 나머지 선택지를 전부 종속시킵니다.

### 상황과 fps는 파일에서 복원되지 않습니다

고아 `.mov`만 보고 복원할 수 있는 것과 없는 것이 갈립니다.

| 복원 가능 | 근거 |
|---|---|
| 세션 경계·시작 시각 | 파일명 접두사 `stamp` (`SwingPipeline.swift:308`) |
| 클립 순서 | 파일명의 `index` (`ClipRecorder.swift:159`) |
| 클립 fps | `.mov` 트랙의 `nominalFrameRate` |

| 복원 불가 | 왜 아픈가 |
|---|---|
| **촬영 상황** (볼머신·벽치기·랠리·시합·레슨) | [IA-FLOW 10.4](../06-디자인/IA-FLOW.md)가 "어느 룰이 유효한지"를 상황으로 정합니다. 모르면 1-D 룰 판정이 무효가 됩니다 — 벽치기인데 모르면 매 스윙 "팔로스루가 부족합니다"를 냅니다 |
| 관찰 대상 (내 스윙 / 라인 판정) | 삼각대 배치 전제가 사라집니다 |

`CaptureSituation`은 옵셔널이 아니고(`CaptureSituation.swift:7`), **"모름"을 표현할 자리가 타입에 없습니다.**

## 범위

### 만들 것

| 무엇 | 어디 |
|---|---|
| 촬영 시작 시 세션 레코드를 연다 (`endedAt == nil`) | `SwingPipeline.begin` — **`open(at:)`이 아니다**(아래 1번) |
| 끝나지 않은 세션 판정 | `SessionRepository` 소비 측 — 미완 세션은 `endedAt == nil` |
| 고아 `.mov`를 세션에 묶는다 | `OrphanClipStore`(`Domain` 선언 · `Presentation` 구현) |
| 복구 — 세션을 닫고 클립을 붙인다 | `RecoverSessionUseCase` (`Domain`) |
| 폐기 — 레코드와 파일을 지운다 | `DiscardSessionUseCase` (`Domain`) |
| 보관함이 미완 세션을 다른 행으로 보여준다 | `LibraryFeature` · 복구/폐기 시트 |
| 복구된 세션을 진단 화면으로 보내지 않는다 | `Session.recoveredAt` 분기 |

### 만들지 않을 것

| 무엇 | 왜 |
|---|---|
| **스윙 구간 재분석** | 고아 클립에는 오버레이 사이드카가 없습니다 — [#121](https://github.com/wnsgur9137/TeniTeni/issues/121)의 사이드카는 `OverlayBakeQueue`가 **리플레이를 열 때** 굽습니다. 재분석하려면 `AVAssetReader` 한 패스 + 포즈 추정을 새로 배선해야 하고, 그것은 이 이슈가 아닙니다. 후속 이슈로 남깁니다 |
| **레코드가 없는 고아 파일의 세션 복원** | 상황과 관찰 대상을 알 수 없습니다. 복원하면 1-D 판정이 조용히 틀립니다. **폐기 대상으로만** 다룹니다 |
| 촬영 중 클립 단위 레코드 갱신 | `save`가 지우고 넣는 방식이라(`SwiftDataSessionRepository.swift:52`) 클립마다 그래프를 전부 다시 씁니다. 120fps 분석 중의 디스크 I/O입니다 |
| 자동 복구 (묻지 않고 복구) | 폐기는 되돌릴 수 없고, 복구된 세션은 스윙 0개라 보관함을 어지럽힙니다. 사용자가 고릅니다 |
| 세션 중간 상태의 진척도 집계 처리 | 2-E가 아직 없습니다. 아래 "리스크"에 전달 사항으로 적습니다 |

## 구현 선택지

### 1. 세션 레코드를 촬영 시작 시 연다

| 안 | 바꾸는 것 | 대가 |
|---|---|---|
| A. 복구할 때 사용자에게 상황을 묻는다 | 복구 화면만 | 사용자가 **틀린 상황을 고르면 지표가 조용히 틀린다** |
| **B. 촬영 시작 시 레코드를 연다** ✅ | `SessionBuilder`에 저장 호출 1개 | `endedAt == nil` 레코드가 앱에 노출된다 |
| C. 도메인에 "상황 모름"을 만든다 | `Session.situation`을 옵셔널/`.unknown` | 1-D 룰이 "판정 불가"를 표현해야 한다. 영향 범위 최대 |

**B를 고릅니다.** 세 가지 근거입니다.

1. **IA-FLOW 10.6의 계약 문구가 그것을 전제합니다.** `"지난 세션이 끝나지 않았습니다"`는 **앱이 세션이 있었다는 것을 안다**는 뜻입니다. A는 파일만 보고 추측하는 것이라 그 문구를 지킬 수 없습니다.
2. **A의 실패가 더 나쁩니다.** 상황을 잘못 고르면 오류도 경고도 없이 룰 판정이 틀립니다. 조용히 틀린 지표는 빈 지표보다 나쁩니다.
3. **스키마를 바꾸지 않습니다.** `endedAt`은 도메인(`Session.swift:8`)과 SwiftData 모델(`SessionModels.swift:18`)에 **이미 있습니다.** 쓰는 쪽이 `duration` 계산뿐이었을 뿐입니다.

#### 어디에 넣는가 — `open(at:)`이 아니라 `begin`이다

처음에는 `SwingPipeline.open(at:)`(세션을 여는 지점)에 적었습니다. **그 자리는 안 됩니다.**

`open(at:)`은 `handle`의 핫 패스에서 불립니다.

```swift
func handle(_ frame: ReadyFrame, pose: PoseFrame?) async -> SwingSnapshot {
    if recorder == nil { open(at: frame.seconds) }   // :166 — 매 프레임 검사
```

`SessionBuilder`는 actor라 `start()`에 `await`가 필요하고, `open(at:)`을 `async`로 바꾸면 **`handle` 안에 `await`가 하나 늘어납니다.** 그 위험은 이 파일이 이미 경고합니다.

> 토큰이 없으면 `end()`가 닫은 세션이 `handle`의 뒤늦은 쓰기로 **되살아나고**, 그 뒤의 모든 녹화가 첫 세션 id로 덮여 레코드가 사라진다.

그리고 `processTrigger`에는 *"`await`가 없다. 그래서 그 사이에 `end()`가 끼어들 틈이 없다"*고 적혀 있습니다.

**`begin`에서 엽니다.** 근거 셋입니다.

1. **레코드에 `clockOrigin`이 들어가지 않습니다.** `open`이 첫 프레임을 기다리는 이유가 프레임 시계 원점인데(`begin`의 주석 — "여기서 세션을 만들지 않는다. 프레임 시계의 원점을 아직 모른다"), `Session`에는 그 필드가 없습니다. 레코드를 여는 데 필요한 것은 `id`·`startedAt`·`situation`·`observable`·`fps`뿐이고 **전부 `begin`의 인자**입니다.
2. **`begin`은 세션당 한 번 불립니다.** 재진입 창이 매 프레임이 아니라 한 번입니다.
3. **호출부가 바뀌지 않습니다.** `CameraController.swift:985`가 이미 `await pipeline.begin(`입니다.

`id`는 `begin`에서 만들어 `Pending`에 담고, `open`이 `SessionBuilder(id:)`로 넘깁니다 — 그래야 **열 때와 닫을 때가 같은 레코드**입니다.

> 덧이득: 첫 프레임이 오기 전에 죽어도 레코드가 남습니다. 그 세션은 `.mov`가 0개이므로 복구할 것이 없고 **폐기만 제안합니다.**

#### 저장이 실패하면 녹화를 막지 않습니다

`start()`가 던지면 `failure`에 담고 **계속 녹화합니다.** 근거는 이미 코드에 적혀 있습니다 — "저장소가 없어도 레코더는 만든다. 클립 파일은 디스크에 남아 복구할 수 있지만, 안 만들면 그조차 없다."

레코드를 못 열어도 `.mov`는 남습니다. 그 파일은 아래 5번에서 **폐기 대상**이 됩니다.

### 2. 고아 `.mov`를 묶는 방법 — 파일명 접두사가 이미 세션 id 역할을 한다

`open(at:)`이 두 값을 **같은 `pending.startedAt`에서** 만듭니다.

```swift
recorder = ClipRecorder(..., stamp: Self.stamp(for: pending.startedAt), ...)
builder  = SessionBuilder(startedAt: pending.startedAt, ...)
```

그리고 `stamp`는 세션당 한 번 고정되고 클립마다 `index`만 올라갑니다(`ClipRecorder.swift:159` — `"\(stamp)-\(index).mov"`). 포맷은 `"yyyyMMdd-HHmmss"` / UTC / `en_US_POSIX`로 결정론적입니다.

따라서 **레코드의 `startedAt`을 `stamp(for:)`에 넣으면 그 세션의 파일명 접두사가 정확히 나옵니다.** 추측이 아니라 기계적 일치입니다.

```
레코드 startedAt  2026-11-05 03:14:15 UTC
       ↓ stamp(for:)
접두사  "20261105-031415"
       ↓ Documents 평면 스캔
파일    20261105-031415-0.mov, 20261105-031415-1.mov, …
```

> ⚠️ **클립 파일은 `Documents` 평면에 있습니다.** 이슈 본문이 "세션 디렉터리의 고아 `.mov`"라고 적었지만 세션별 디렉터리는 없습니다 — `SwingPipeline`의 `directory`가 `URL.documentsDirectory`입니다.

#### 스캔은 `Domain` 밖에서 한다

[ARCHITECTURE 2.2](../02-설계/ARCHITECTURE.md)가 `Domain`을 **"순수 Swift, 의존성 0"**으로 정했고 실제로 `Domain/Sources`의 import는 `Foundation` 하나뿐입니다. 그런데 복구는 **디렉터리 스캔**과 **`.mov` 트랙 fps 읽기**(`AVFoundation`)를 요구합니다. 둘 다 `Domain`에 넣을 수 없습니다 — 앱 컨테이너 경로를 `Domain`이 아는 것도 같은 이유로 안 됩니다.

`ClipFileStore`를 `Domain`이 **프로토콜로만** 선언하고 `DocumentsClipFileStore`를 `Presentation`에 둔 것과 같은 패턴을 씁니다.

```swift
// Domain — 선언만
public protocol OrphanClipStore: Sendable {
    /// 그 세션의 고아 클립. 파일명 접두사로 찾는다.
    func orphans(for session: Session) async -> [OrphanClip]
}

public struct OrphanClip: Sendable, Equatable {
    public let fileName: String
    public let recordedAt: Date
    public let fps: Int
}
```

`Presentation`의 구현(`DocumentsOrphanClipStore`)이 접두사 계산·디렉터리 스캔·`AVAsset` 읽기를 전부 가져갑니다. 유스케이스는 `Domain`에 남습니다.

이 가름은 테스트도 싸게 만듭니다 — **유스케이스 테스트에 실제 `.mov`가 필요 없어집니다.**

#### 스캔은 맨 이름만 본다

`DocumentsClipFileStore.isSafe(_:)`가 이미 같은 함정을 다룹니다(`../`·`sub/`·빈 이름). 스캔도 **하위 디렉터리로 내려가지 않고** `contentsOfDirectory`의 맨 이름만 봅니다. 접두사가 일치하고 확장자가 `.mov`인 것만 고릅니다.

사이드카(`*.mov.overlay.json`)는 접두사가 같지만 확장자가 다르므로 걸리지 않습니다.

### 3. 복구한 클립의 `recordedAt`은 파일 생성 시각으로 둔다

`Clip.recordedAt`은 옵셔널이 아닙니다. 파일명에는 `index`만 있고 시각이 없습니다.

| 안 | 문제 |
|---|---|
| `session.startedAt`을 그대로 | 클립 n개가 **전부 같은 시각**이 된다. 보관함·리플레이 정렬이 무의미해진다 |
| 파일의 `contentModificationDate` | 녹화가 **끝난** 시각이다. 정상 경로와 뜻이 다르다 |
| **`creationDate`** ✅ | 녹화가 **시작된** 시각. 정상 경로와 뜻이 가장 가깝다 |

> ⚠️ **정상 경로와 같은 값은 아닙니다.** 정상 경로의 `recordedAt`은 `sessionStartedAt + (프레임 시계 경과)`입니다(`SessionBuilder.clip(from:…)`). 복구 경로는 파일시스템 시계를 씁니다. 같은 뜻을 가리키지만 **값은 수십~수백 ms 다를 수 있습니다.** 스윙 구간이 없는 세션이라 그 차이가 분석에 쓰이지는 않습니다.

속성을 읽지 못하면 `index` 순서를 유지하도록 `session.startedAt`에 `index`초를 더해 둡니다 — 정렬만 지키고 값은 신뢰하지 않습니다.

### 4. 복구한 클립의 스윙 구간 — 비워 두고, 비웠다는 것을 레코드에 남긴다

| 안 | 대가 |
|---|---|
| 다시 분석한다 | 고아 클립에 사이드카가 없어 `AVAssetReader` 한 패스 + 포즈 배선이 필요합니다. 이 이슈의 범위를 넘습니다 |
| 그냥 비워 둔다 | **아래 충돌에 걸립니다** |
| **비워 두고 `recoveredAt`을 남긴다** ✅ | 필드 하나가 늡니다 |

#### ⚠️ 비워 두기만 하면 진단 화면이 거짓을 말합니다

[IA-FLOW 10.6](../06-디자인/IA-FLOW.md)이 정했습니다 — **"스윙 0개로 종료 → 진단 화면"**. 그 화면의 문구는 이렇습니다.

```
스윙을 하나도 찾지 못했습니다

확인할 것
  · 선수가 프레임 안에 들어왔나요
  · 삼각대가 흔들리지 않았나요
  · 거리가 5~8m 범위였나요
```

복구한 세션은 **스윙이 없는 것이 아니라 분석을 하지 않은 것**입니다. 이 화면으로 보내면 사용자는 삼각대를 확인하러 갑니다 — 문제는 삼각대가 아닙니다.

그래서 **"스윙 0개"와 "분석되지 않음"을 구분해야 하고**, `swings.isEmpty`만으로는 구분되지 않습니다. 필드 하나를 둡니다.

```swift
/// 강제 종료 뒤 복구된 세션인가. **스윙 0개의 뜻을 가른다** —
/// 못 찾은 것이 아니라 분석하지 않은 것이다.
public var recoveredAt: Date?
```

복구 화면과 보관함 행은 **"영상은 살렸고 스윙 구간은 없습니다"**를 명시합니다. 영상이 사용자가 잃은 것이고, 그것을 되찾는 것이 이 이슈의 가치입니다.

### 5. 폐기 — #126의 삭제를 그대로 쓸 수 없다

[#126](https://github.com/wnsgur9137/TeniTeni/issues/126)의 `DeleteSessionUseCase`는 **레코드의 `clips`를 돌며** 파일을 지웁니다(`DeleteSession.swift`). 미완 세션의 레코드에는 **클립이 0개**입니다 — 촬영 중에는 레코드를 갱신하지 않기 때문입니다(위 "만들지 않을 것").

그대로 쓰면 레코드만 사라지고 **고아 `.mov`가 그대로 남습니다.** 그래서 폐기는 2번의 스캔으로 파일을 찾아 지웁니다.

순서는 #126의 결정을 따릅니다 — **파일 먼저, 레코드 나중에.** 근거도 같습니다: 레코드를 먼저 지우면 실패 시 **보이지 않는** 고아 파일이 남고, 파일을 먼저 지우면 [#120](https://github.com/wnsgur9137/TeniTeni/issues/120)이 "영상이 없습니다"로 **보여주는** 빈 레코드가 남습니다.

확인 문구에는 #126과 같이 **숫자를 적습니다** — "클립 3개". 스윙 수는 모르므로 적지 않습니다(분석하지 않았습니다).

> ⚠️ **그 숫자는 스캔 결과입니다.** 미완 세션의 레코드에는 클립이 0개이므로, `clips.count`로 구현하면 **항상 "클립 0개"로 뜹니다.** #126이 확인 문구를 "절차가 아니라 확인"으로 만든 근거가 그 숫자인데, 0개로 뜨면 그 근거가 무너집니다.

### 6. 언제 묻나 — 모달이 아니라 보관함의 행으로 보여준다

| 안 | 대가 |
|---|---|
| 앱 시작 즉시 모달 | 콜드 스타트를 막습니다. 사용자가 급히 촬영하려는데 **요청하지 않은 결정**을 강요합니다. 미루면 매 실행 뜹니다 |
| 촬영 탭 진입 시 | 촬영하려는 순간을 막습니다. 같은 문제입니다 |
| **보관함 목록의 행** ✅ | 사용자가 그 행을 탭할 때까지 아무것도 강요하지 않습니다 |

**보관함이 이미 같은 성격의 상태를 행으로 처리하는 선례입니다.** [#120](https://github.com/wnsgur9137/TeniTeni/issues/120)이 레코드-파일 불일치를 `"영상이 없습니다"` 행으로 보여줍니다([SPEC-0120](SPEC-0120-missing-clip.md)). 미완 세션도 레코드와 파일이 어긋난 상태이고, 같은 자리에서 같은 방식으로 말하는 것이 일관됩니다.

그리고 **보관함은 "찍은 것이 살아 있다는 증거"**입니다([SPEC-0116](SPEC-0116-session-library.md)). 사용자가 "어제 찍은 거 어디 갔지?"를 확인하러 가는 곳이 거기입니다.

#### 미완 세션은 `ClipAvailability` 판정을 건너뛴다

[#120](https://github.com/wnsgur9137/TeniTeni/issues/120)이 보관함 행마다 파일 존재를 확인해 `"영상이 없습니다"`를 띄웁니다. 미완 세션의 레코드는 **클립이 0개**이므로, 그 판정을 그대로 태우면 `"영상이 없습니다"`와 `"복구할 수 있습니다"`가 **동시에** 뜰 수 있습니다. 둘은 모순입니다 — 영상은 디스크에 있습니다.

미완 세션은 판정 대상에서 뺍니다. 그 행이 할 말은 "복구할 수 있습니다" 하나입니다.

#### 목록에서 맨 위에 온다

`LibraryFeature`는 `loadAll()`의 "최근 것부터"를 믿지 않고 **직접 정렬합니다**(`:146`). 미완 세션은 `endedAt`이 없으므로 정렬 키는 `startedAt`입니다. 가장 최근이라 맨 위에 오고, 그것이 맞습니다 — 사용자가 찾는 것이 그것입니다.

> ⚠️ **IA-FLOW 10.6을 보정합니다.** 그 표의 화면 칸이 `"지난 세션이 끝나지 않았습니다"`로만 적혀 있어 전용 화면/모달로 읽힙니다. 이 기획서가 그것을 **보관함 행 + 복구/폐기 시트**로 바꿉니다. 문구 자체는 그대로 씁니다.

## 구현에서 달라진 것 (2026-11-05)

기획서가 정하지 않아 **구현이 멈췄던 자리** 둘과, 구현하며 드러난 것 둘입니다.

### 1. 복구한 세션의 `endedAt`은 마지막 클립 시각이다

강제 종료 시각은 아무도 모릅니다. `now`를 쓰면 **어제 죽은 세션의 `duration`이 하루**가 되고, 보관함과 세션 비교가 그 값을 읽습니다. 마지막 클립의 `recordedAt`으로 둡니다 — 실제보다 약간 짧지만 터무니없지 않습니다.

### 2. 첫 프레임 전에 정지하면 레코드를 지운다

`begin`이 레코드를 열고 `open(at:)`이 첫 프레임에서 `SessionBuilder`를 만듭니다. 그 사이에 정지하면 **`end`가 닫을 `builder`가 없어** 레코드가 `endedAt == nil`로 남습니다.

그러면 녹화를 눌렀다 바로 끈 사용자에게 **보관함의 "복구할 수 있습니다" 행이 매번** 뜨는데, 복구할 영상이 하나도 없습니다. 그래서 `end`가 그 레코드를 지웁니다.

> 기획서가 ".mov가 0개인 미완 세션은 폐기만 제안한다"고 적었지만, 그것은 **강제 종료된 경우**의 처리입니다. 정상적으로 끈 경우까지 그 행을 보여줄 이유가 없습니다.

### 3. 진단 판정을 `Domain`으로 올렸다

`recoveredAt` 분기를 넣으려다 보니 **같은 조건이 두 곳에** 있었습니다 — `SessionSummaryFeature.isDiagnosis`와 `SessionSummaryView`의 `session.swingCount == 0`. 한쪽만 고치면 상태와 화면이 어긋납니다. `Session.needsDiagnosis`로 합쳤습니다.

### 4. ⚠️ 테스트 fixture가 **저장될 수 없는 상태**를 쓰고 있었다

`endedAt`은 기본값이 `nil`이라 테스트들이 그것을 생략했습니다. 그전에는 `nil`인 레코드가 저장될 수 없었으므로 무해했지만, 이제 **"끝나지 않은 세션"을 뜻합니다.**

`MissingClipFlowTests`·`DeleteFlowTests`의 fixture를 닫힌 세션으로 고쳤습니다. 다른 테스트 파일에도 같은 생략이 있지만 미완 여부가 그 경로의 동작을 바꾸지 않아 그대로 두었습니다 — 구현 PR에 목록을 적습니다.

그리고 `SwingPipelineTests`의 가짜 저장소가 `save`를 **append**하고 있었습니다. 실물은 upsert입니다(`SwiftDataSessionRepository.save`가 같은 id를 지우고 넣습니다). 가짜가 실물의 계약을 어기면 그 테스트는 아무것도 보장하지 않으므로 upsert로 고쳤습니다. `delete`도 빈 구현이었습니다.

## 데이터 모델

### 추가

```swift
// Domain/Session.swift
public struct Session {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?        // ← 이미 있다. 이제 nil이 실제로 생긴다
    public var recoveredAt: Date?    // ← 신규
    …
}
```

| 필드 | 뜻 |
|---|---|
| `endedAt == nil` | **끝나지 않은 세션.** 촬영 중이거나, 강제 종료됐다 |
| `recoveredAt != nil` | 복구된 세션. 스윙 0개는 "못 찾았다"가 아니라 "분석하지 않았다"다 |

### SwiftData 마이그레이션

`SessionModel`에 `var recoveredAt: Date?`를 더합니다. **옵셔널 필드 추가는 SwiftData의 경량 마이그레이션이 자동 처리합니다.** 더해서 TestFlight 전이라 기존 데이터도 없습니다.

### 파생

```swift
public var isUnfinished: Bool { endedAt == nil }
```

`duration`은 지금도 `endedAt.map { … }`이라 `nil`에서 `nil`을 줍니다 — 바꿀 것이 없습니다.

## 완료 기준

전부 시뮬레이터 단위 테스트로 확인합니다.

- [x] `begin`이 `endedAt == nil`인 세션을 저장한다
- [ ] `finish(at:)`이 **같은 id로** `endedAt`을 채워 덮는다 — 레코드가 2건이 되지 않는다
- [ ] `begin`의 저장이 던져도 녹화가 계속된다 (`failure`에 담기고 레코더는 산다)
- [ ] `open(at:)`은 **`async`가 되지 않는다** — `handle`의 `await` 개수가 늘지 않는다
- [ ] 접두사 스캔이 **그 세션의 파일만** 고른다 — 다른 stamp의 `.mov`, 사이드카 `.json`, 하위 디렉터리의 파일을 섞어 두고 확인
- [ ] 스캔·fps 읽기가 `OrphanClipStore` 구현에 있고 **`Domain`은 `Foundation`만 import한다**
- [ ] 복구가 `endedAt`·`recoveredAt`을 채우고 클립 n개를 `index` 순서로 붙인다
- [ ] 복구한 클립의 `fps`를 `.mov` 트랙에서 읽는다 — 세션 fps를 그대로 쓰지 않는다([ADR-0005](../05-결정/adr/ADR-0005-thermal-auto-adjust.md)의 강등을 걸친 세션이 틀어진다)
- [ ] 복구한 클립의 `recordedAt`이 **클립마다 다르다** — 전부 같은 값이면 정렬이 무의미하다
- [ ] 폐기가 **파일을 먼저** 지우고 레코드를 나중에 지운다 (호출 순서를 기록해 확인)
- [ ] 폐기가 레코드에 없는 고아 파일까지 지운다
- [ ] 폐기 확인 문구의 클립 수가 **스캔 결과**다 — 레코드의 `clips.count`(항상 0)가 아니다
- [ ] 보관함이 미완 세션을 완료 세션과 **다른 행**으로 보여준다
- [ ] 미완 세션 행에 `"영상이 없습니다"`가 **함께 뜨지 않는다**
- [ ] 미완 세션이 목록 맨 위에 온다
- [ ] `swingCount == 0`이고 `recoveredAt != nil`인 세션을 **진단 화면으로 보내지 않는다**
- [ ] `.mov`가 0개인 미완 세션은 **폐기만 제안한다**
- [ ] 미완 세션이 없으면 보관함이 지금과 똑같이 동작한다 (회귀)

## 검증 방법

| 무엇 | 어떻게 |
|---|---|
| 레코드 열기·닫기 | `SwingPipelineTests`·`SessionBuilderTests` — 가짜 저장소가 `save` 호출을 기록 |
| 복구·폐기 유스케이스 | 가짜 `OrphanClipStore`를 넣는다 — **실제 `.mov` 불필요** |
| 접두사 스캔 | 임시 디렉터리에 파일을 깔고 확인. 실기기 불필요 |
| 복구·폐기 순서 | `Journal` actor로 호출 순서 기록 — `DeleteSessionTests`의 방식을 그대로 |
| 클립 fps 읽기 | 합성 `.mov`를 만들어 트랙 fps를 확인 (`SPEC-0091`의 합성 픽셀 버퍼 방식) |
| 보관함 행 | `LibraryFeatureTests` TCA 스토어 테스트 |

### ⚠️ 실기기로만 할 수 있는 것

**강제 종료 자체는 단위 테스트로 만들 수 없습니다.** 테스트는 "레코드가 `endedAt == nil`로 남고 `.mov`가 디스크에 있는 상태"를 **인공적으로** 만들어 그 뒤를 검증합니다. 그 상태가 실제 강제 종료로 만들어지는지는 실기기에서 앱을 죽여 봐야 합니다.

이것은 **미수행으로 남깁니다.** PR 본문에 명시합니다.

## 영향받는 문서

| 문서 | 무엇 |
|---|---|
| [IA-FLOW](../06-디자인/IA-FLOW.md) 10.6 | "앱 강제 종료" 행의 화면 칸 → 보관함 행 + 시트. "스윙 0개는 진단" 절에 복구 세션 예외 |
| [IA-FLOW](../06-디자인/IA-FLOW.md) 10.10 | 신규 아트보드 행 |
| [ARCHITECTURE](../02-설계/ARCHITECTURE.md) 2.4 | `Session.recoveredAt` |
| [INDEX](../INDEX.md) | 이 기획서 등재 |
| [WORK-PLAN](../04-계획/WORK-PLAN.md) 9.5 | 2-E에 "미완 세션은 집계에서 뺀다" 전달 |

## 리스크

| 리스크 | 대응 |
|---|---|
| **`endedAt == nil` 레코드가 진척도 집계에 섞인다** | 2-E가 아직 없습니다. WORK-PLAN 9.5에 전달 사항으로 적습니다 — 미완 세션은 집계에서 뺍니다 |
| 촬영 중에 보관함을 열면 **지금 찍고 있는 세션**이 미완으로 보인다 | 실제로 미완입니다. 다만 "복구"를 제안하면 안 됩니다. 행은 보여주되 시트는 열지 않습니다 — 탭하면 "촬영 중입니다"로 끝냅니다 |
| 같은 초에 두 세션이 시작되면 stamp가 충돌한다 | 촬영 시작 사이에 최소 수 초가 걸려 현실적으로 불가합니다. 충돌하면 두 세션의 파일이 한쪽에 붙습니다 — 감지만 하고 막지 않습니다 |
| 레코드 저장이 실패한 세션의 `.mov`는 주인이 없다 | 복구하지 않습니다(상황을 모릅니다). [#124](https://github.com/wnsgur9137/TeniTeni/issues/124)의 저장공간 정리가 다룰 대상입니다 |
| 복구된 세션이 스윙 0개라 보관함이 지저분해진다 | 폐기를 같은 자리에서 고를 수 있게 둡니다 |

## 미수행으로 남길 것

- **실기기 강제 종료 검증** — 앱을 실제로 죽여 레코드와 파일이 예상대로 남는지. 위 "검증 방법" 참조
- **스윙 구간 재분석** — [#121](https://github.com/wnsgur9137/TeniTeni/issues/121) 이후 별도 이슈. 고아 클립에 사이드카가 없어 `AVAssetReader` 패스가 필요합니다
- **레코드 없는 고아 파일의 세션 복원** — 상황을 알 수 없습니다
- **미완 세션의 진척도 집계 처리** — 2-E의 범위

## 관련 문서

- [IA-FLOW](../06-디자인/IA-FLOW.md) 10.4 촬영 상황 · 10.6 예외 경로
- [SPEC-0097](SPEC-0097-swing-wiring.md) 스윙 검출 배선 — `SwingPipeline`·`SessionBuilder`의 출처
- [SPEC-0110](SPEC-0110-session-summary.md) 세션 요약과 스윙 0개 진단
- [SPEC-0116](SPEC-0116-session-library.md) 보관함 세션 목록
- [SPEC-0120](SPEC-0120-missing-clip.md) 파일이 없는 클립을 목록이 말한다 — 같은 성격의 선례
- [SPEC-0126](SPEC-0126-delete.md) 세션과 클립을 지운다 — 폐기가 그 순서를 따릅니다
- [ADR-0005](../05-결정/adr/ADR-0005-thermal-auto-adjust.md) 발열 자동 조정 — 클립마다 fps가 다른 이유
