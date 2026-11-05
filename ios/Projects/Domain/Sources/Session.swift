import Foundation

/// 한 번의 연습. 촬영 시작~종료까지의 단위.
/// 근거: docs/01-제품/PRODUCT-OVERVIEW.md 1.7 용어집
public struct Session: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date

    /// `nil`이면 **끝나지 않은 세션**이다 — 촬영 중이거나, 앱이 강제
    /// 종료됐다. 촬영을 시작할 때 레코드를 먼저 열기 때문에 생긴다.
    ///
    /// 그 전에는 저장 호출이 `SessionBuilder.finish` 하나뿐이라 이 값이
    /// `nil`인 레코드가 **생길 수 없었다.** 그래서 강제 종료되면 레코드가
    /// 0건이고 고아 `.mov`만 남았다.
    ///
    /// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 1
    public var endedAt: Date?

    /// 강제 종료 뒤 복구된 세션인가. **스윙 0개의 뜻을 가른다.**
    ///
    /// 복구한 클립에는 스윙 구간이 없다 — 고아 클립에 오버레이 사이드카가
    /// 없어 재분석이 이 작업의 범위를 넘었다. 그래서 `swingCount == 0`이
    /// 두 가지를 뜻하게 된다.
    ///
    /// | 상태 | 뜻 | 화면 |
    /// |---|---|---|
    /// | `recoveredAt == nil` | 스윙을 **못 찾았다** | 진단 (`EmptySession`) |
    /// | `recoveredAt != nil` | **분석하지 않았다** | 요약 |
    ///
    /// 가르지 않으면 복구된 세션에 "삼각대가 흔들리지 않았나요"를 묻는다.
    /// 문제는 삼각대가 아니다.
    ///
    /// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 4
    public var recoveredAt: Date?

    /// 어떤 상황에서 찍었는가. 세션 간 비교 시 상황이 다르면 나란히 놓지
    /// 않는다 — 스트로크 길이 자체가 다르다 (IA-FLOW 10.4).
    public let situation: CaptureSituation
    public let observable: ObservationTarget
    public let fps: Int

    public var clips: [Clip]

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// 끝나지 않은 세션. 촬영 중이거나 강제 종료됐다.
    ///
    /// **둘을 여기서 구분하지 않는다.** 구분하는 것은 호출부다 — 촬영
    /// 중인 세션은 지금 화면이 알고 있고, 보관함은 모른다.
    public var isUnfinished: Bool { endedAt == nil }

    /// 스윙이 하나도 없으면 요약이 아니라 진단 화면을 띄운다 —
    /// 빈 요약은 "앱이 고장났다"로 읽힌다 (IA-FLOW 10.6).
    public var swingCount: Int { clips.reduce(0) { $0 + $1.swings.count } }

    /// 스윙 0개를 **진단으로 다룰 것인가.**
    ///
    /// `swingCount == 0`만 보면 안 된다. 복구된 세션도 0개인데 그쪽은
    /// **못 찾은 것이 아니라 분석하지 않은 것**이다. 진단 화면은
    /// "삼각대가 흔들리지 않았나요"를 묻는데, 복구된 세션의 문제는
    /// 삼각대가 아니다.
    ///
    /// 판정을 여기 두는 이유: 요약 리듀서와 뷰가 **각각** 같은 조건을
    /// 적고 있었다. 한쪽만 고치면 화면과 상태가 어긋난다.
    ///
    /// 근거: docs/07-기획/SPEC-0125-crash-recovery.md 선택지 4
    public var needsDiagnosis: Bool { swingCount == 0 && recoveredAt == nil }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        recoveredAt: Date? = nil,
        situation: CaptureSituation,
        observable: ObservationTarget = .swing,
        fps: Int,
        clips: [Clip] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.recoveredAt = recoveredAt
        self.situation = situation
        self.observable = observable
        self.fps = fps
        self.clips = clips
    }
}

/// 세션 중 저장된 영상 파일. **촬영 fps를 함께 기록한다.**
///
/// fps를 클립에도 두는 이유는 세션 도중 바뀔 수 있기 때문이다 — 발열로
/// 120fps에서 60fps로 낮추는 경로가 있다 (IA-FLOW 10.6).
public struct Clip: Identifiable, Equatable, Sendable {
    /// ⚠️ **다른 세션에 담을 때는 새 id를 준다.** 저장 계층에서 클립 id는
    /// 전역 unique이고, SwiftData의 unique 제약은 충돌을 에러가 아니라
    /// upsert로 해소한다. 같은 id의 클립을 다른 세션으로 저장하면 그 행의
    /// 소속이 조용히 옮겨가 원래 세션에서 사라진다.
    public let id: UUID
    /// 영상 파일 경로. 파일 자체는 SwiftData에 넣지 않는다 — D-08이
    /// "메타데이터만"으로 확정했다.
    public var fileName: String
    public let recordedAt: Date
    public let fps: Int
    public var swings: [Swing]

    public init(
        id: UUID = UUID(),
        fileName: String,
        recordedAt: Date,
        fps: Int,
        swings: [Swing] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.fps = fps
        self.swings = swings
    }
}

/// 자동 검출된 한 번의 스윙. **클립 내 시간 구간으로 표현한다.**
public struct Swing: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    /// 임팩트 순간. 대부분의 지표가 이 프레임에서 계산된다
    /// (IA-FLOW 10.8의 "기본 재생 위치도 임팩트").
    public let impactSeconds: TimeInterval
    /// 1-D의 분류기가 채운다. 그전에는 `nil`.
    public var kind: SwingKind?

    public var duration: TimeInterval { endSeconds - startSeconds }

    public init(
        id: UUID = UUID(),
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        impactSeconds: TimeInterval,
        kind: SwingKind? = nil
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.impactSeconds = impactSeconds
        self.kind = kind
    }
}

/// 스윙 유형 4종. 분류는 1-D다 — 여기서는 담을 자리만 만든다.
public enum SwingKind: String, Sendable, CaseIterable {
    case forehand
    case backhand
    case serve
    case volley

    public var label: String {
        switch self {
        case .forehand: "포핸드"
        case .backhand: "백핸드"
        case .serve: "서브"
        case .volley: "발리"
        }
    }
}
