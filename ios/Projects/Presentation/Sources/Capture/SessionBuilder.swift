import Domain
import Foundation
import TeniVision

/// 촬영 한 번 동안 쌓인 클립을 세션 하나로 묶어 저장한다.
///
/// ## 왜 여기인가
///
/// `TeniVision`은 `Domain`을 모르고(계층 구조상 의존성 0), `Domain`도
/// `TeniVision`을 모른다. 둘을 **함께 아는 가장 낮은 계층**이
/// `Presentation`이다 — [아키텍처 2.2](../../../../../docs/02-설계/ARCHITECTURE.md).
///
/// ## 왜 actor인가
///
/// 클립은 쓰기가 끝날 때마다 하나씩 들어오고, 그것을 모으는 동안 촬영은
/// 계속된다. 저장은 `SessionRepository`(actor 구현)를 거친다.
///
/// 근거: docs/07-기획/SPEC-0091-swing-clip-recording.md
public actor SessionBuilder {

    private let repository: any SessionRepository
    private let id: UUID
    private let startedAt: Date
    private let clockOrigin: TimeInterval
    private let situation: CaptureSituation
    private let observable: ObservationTarget
    private let fps: Int
    private var clips: [Clip] = []

    /// - Parameters:
    ///   - startedAt: 세션이 시작된 **벽시계** 시각.
    ///   - clockOrigin: 그 순간의 **프레임 시계** 값. 둘을 맞추는 값이다.
    ///
    /// `RecordedClip.startedAt`은 프레임 시계다 — 카메라가 배선되면
    /// `CMSampleBuffer.presentationTimeStamp`, 즉 **부팅 이후 호스트
    /// 시각**이 된다. 그것을 그대로 세션 시작에 더하면 부팅 후 11시간 된
    /// 기기에서 클립이 11시간 뒤로 기록된다 — 오류도 경고도 없이 보관함
    /// 정렬과 세션 비교가 전부 틀어진다. 그래서 원점을 받아 뺀다.
    public init(
        id: UUID = UUID(),
        startedAt: Date,
        clockOrigin: TimeInterval,
        situation: CaptureSituation,
        observable: ObservationTarget = .swing,
        fps: Int,
        repository: any SessionRepository
    ) {
        self.id = id
        self.startedAt = startedAt
        self.clockOrigin = clockOrigin
        self.situation = situation
        self.observable = observable
        self.fps = fps
        self.repository = repository
    }

    public var clipCount: Int { clips.count }

    public func add(_ recorded: RecordedClip) {
        clips.append(
            Self.clip(
                from: recorded, fps: fps, sessionStartedAt: startedAt, clockOrigin: clockOrigin
            )
        )
    }

    /// 세션을 닫아 저장하고 저장한 것을 돌려준다.
    ///
    /// 클립이 하나도 없어도 저장한다 — **스윙 0개도 결과다.** 그것을 버리면
    /// 진단 화면(`EmptySession`)이 보여줄 것이 없어진다.
    @discardableResult
    public func finish(at endedAt: Date) async throws -> Session {
        let session = Session(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            situation: situation,
            observable: observable,
            fps: fps,
            clips: clips
        )
        try await repository.save(session)
        return session
    }

    /// `RecordedClip`을 도메인 엔티티로 옮긴다.
    ///
    /// 파일명만 담고 디렉터리는 버린다 — 앱 컨테이너 경로는 재설치마다
    /// 바뀌므로 DB에 절대경로를 넣으면 전부 깨진다.
    static func clip(
        from recorded: RecordedClip,
        fps: Int,
        sessionStartedAt: Date,
        clockOrigin: TimeInterval
    ) -> Clip {
        // 프레임 시계를 세션 시작으로부터의 경과로 바꾼다. 음수가 되면
        // 원점이 틀린 것이지 과거에 찍힌 것이 아니므로 0으로 둔다.
        let elapsed = max(0, recorded.startedAt - clockOrigin)
        return Clip(
            fileName: recorded.url.lastPathComponent,
            recordedAt: sessionStartedAt.addingTimeInterval(elapsed),
            fps: fps,
            swings: recorded.swings.map { swing in
                Swing(
                    startSeconds: swing.startSeconds,
                    endSeconds: swing.endSeconds,
                    impactSeconds: swing.impactSeconds
                )
            }
        )
    }
}
