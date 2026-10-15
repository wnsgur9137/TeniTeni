import Foundation

/// 한 번의 연습. 촬영 시작~종료까지의 단위.
/// 근거: docs/01-제품/PRODUCT-OVERVIEW.md 1.7 용어집
public struct Session: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?

    /// 어떤 상황에서 찍었는가. 세션 간 비교 시 상황이 다르면 나란히 놓지
    /// 않는다 — 스트로크 길이 자체가 다르다 (IA-FLOW 10.4).
    public let situation: CaptureSituation
    public let observable: ObservationTarget
    public let fps: Int

    public var clips: [Clip]

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    /// 스윙이 하나도 없으면 요약이 아니라 진단 화면을 띄운다 —
    /// 빈 요약은 "앱이 고장났다"로 읽힌다 (IA-FLOW 10.6).
    public var swingCount: Int { clips.reduce(0) { $0 + $1.swings.count } }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        situation: CaptureSituation,
        observable: ObservationTarget = .swing,
        fps: Int,
        clips: [Clip] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
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
