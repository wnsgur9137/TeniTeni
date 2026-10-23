import Foundation

/// 프레임을 들고 있다가 스윙 구간을 클립 파일로 쓴다.
///
/// 스윙은 **끝난 뒤에** 검출된다. 테이크백은 이미 지나갔으므로 계속 담고
/// 있다가 되감아야 한다 — [아키텍처 2.3](../../../../docs/02-설계/ARCHITECTURE.md).
///
/// ## 버퍼는 `preRoll`만 들고 있는다
///
/// 설계 2.3이 "링 버퍼(최근 5초)"라고 적었지만, 쓰기를 스트리밍으로 하면
/// **소급분만 버퍼에 있으면 된다.** 구간이 열리는 순간 소급분을 쓰고, 그
/// 뒤의 프레임은 들어오는 대로 바로 쓴다.
///
/// 배열로 모아 한 번에 쓰는 설계라면 버퍼가 클립 전체를 들고 있어야 하고,
/// 겹침 병합으로 구간이 길어지면 **머리가 조용히 버려진다.** 그래서
/// 스트리밍으로 바꿨다.
///
/// ## 왜 actor인가
///
/// [동시성 6.2](../../../../docs/02-설계/CONCURRENCY.md)가 `ClipRecorder`를
/// `actor`로 정했다 — 링 버퍼와 `AVAssetWriter` 상태를 보호한다. 프레임
/// 인테이크는 `nonisolated`한 캡처 큐에서 들어온다.
///
/// `SwingTrigger`가 `actor`가 아닌 것과 모순이 아니다. 트리거는 **순서가
/// 절대적인 순수 계산**이라 단일 Task에 둬야 하고, 이쪽은 **공유 상태
/// 보호**가 목적이다.
///
/// ## 쓰기가 actor를 막는다
///
/// `append`는 인코더가 받아줄 때까지 돌아오지 않고 그동안 `enqueue`도
/// 막힌다. 프레임 하나씩이라 배열을 한 번에 쓰는 것보다 짧지만 0은
/// 아니다 — 실기기에서 재야 할 비용이다. 기획서 리스크 표에 적었다.
///
/// 근거: docs/07-기획/SPEC-0091-swing-clip-recording.md
public actor ClipRecorder<Frame: ClipFrame> {

    private var buffer: TimedRingBuffer<Frame>
    private var planner = ClipPlanner()
    private var session: ClipWriter.Session?
    private let directory: URL
    private let stamp: String
    private var index = 0

    /// - Parameters:
    ///   - profile: 버퍼 창을 여기서 끌어낸다 — `preRoll + margin`. 창을
    ///     직접 받으면 `preRoll`보다 짧게 줄 수 있고, 그러면 **소급분이
    ///     모자란 채 조용히 지나간다.**
    ///   - margin: 트리거가 교차 프레임보다 늦게 발화하는 만큼의 여유.
    ///     최소 지속시간(`minimumDuration`)만큼 뒤에 울린다.
    ///   - stamp: 파일명 접두사. 시각 포매팅을 밖에 두면 테스트가
    ///     결정론적이다.
    public init(
        profile: SwingTriggerProfile = .default,
        margin: TimeInterval = 1.0,
        directory: URL,
        stamp: String
    ) {
        precondition(margin > 0, "여유는 0보다 커야 한다")
        self.buffer = TimedRingBuffer(window: profile.preRoll + margin)
        self.directory = directory
        self.stamp = stamp
    }

    /// 들고 있는 프레임 수. 진단용이다.
    public var bufferedFrameCount: Int { buffer.count }

    /// 아직 닫히지 않은 구간이 있는지.
    public var hasOpenSegment: Bool { planner.isOpen }

    /// 지금까지 연 클립 수. 파일명의 연번과 같다.
    public var clipCount: Int { index }

    /// 프레임을 담는다.
    ///
    /// 열린 구간이 이 프레임보다 먼저 끝났으면 클립을 닫아 돌려준다.
    /// 구간 안이면 바로 쓴다.
    public func enqueue(_ frame: Frame) throws -> RecordedClip? {
        buffer.append(frame, at: frame.seconds)

        // 구간 밖의 첫 프레임이다 — 클립에 넣지 않고 닫는다.
        if let closed = planner.advance(to: frame.seconds) {
            return try closeSession(closed)
        }

        guard planner.isOpen else { return nil }
        if session == nil {
            // 구간이 막 열렸거나, 소급분이 비어 아직 못 열었던 경우.
            // 이 프레임이 버퍼에 들어왔으니 이제 열린다.
            try openSession()
        } else {
            try session?.append(frame)
        }
        return nil
    }

    /// 후보를 받는다. 앞선 구간이 이것과 겹치지 않으면 그 구간을 닫는다.
    ///
    /// **세션을 여기서 열지 않는다.** 닫기에 성공해 파일이 디스크에 생겼는데
    /// 이어지는 열기가 던지면, 완성된 `RecordedClip`이 반환되지 못하고
    /// 사라진다 — 파일은 있고 기록은 없는 고아가 된다. 열기는 다음
    /// `enqueue`가 맡는다.
    public func accept(_ candidate: SwingCandidate) throws -> RecordedClip? {
        // 트리거가 버퍼 창보다 늦게 울리면 임팩트 프레임이 이미 버려졌고,
        // 상대초 클램프가 그것을 0초(= 첫 프레임)로 둔갑시킨다. 조용히
        // 틀린 프레임을 분석하게 되므로 디버그에서 잡는다.
        assert(
            candidate.triggeredAt >= (buffer.oldest ?? -.infinity),
            "트리거가 버퍼 창보다 늦게 울렸다 — 임팩트 프레임이 없다"
        )
        guard let closed = planner.accept(candidate) else { return nil }
        return try closeSession(closed)
    }

    /// 세션을 끝낸다. `postRoll`을 못 채운 구간도 **가진 만큼** 쓴다 —
    /// 마지막 스윙을 버리지 않는다.
    ///
    /// 두 번 불러도 같은 세션을 다시 저장하지 않는다.
    public func finish() throws -> RecordedClip? {
        // 후보가 들어온 뒤 프레임이 하나도 오지 않았으면 세션이 아직
        // 없다. 버퍼의 소급분으로 지금 연다 — 안 열면 마지막 스윙이
        // 통째로 사라진다.
        if session == nil { try openSession() }
        guard let segment = planner.finish() else { return nil }
        return try closeSession(segment)
    }

    /// 열린 구간이 있고 세션이 없으면, 소급분을 써서 세션을 연다.
    private func openSession() throws {
        guard session == nil, let range = planner.openRange else { return }
        let backlog = buffer.slice(from: range.lowerBound, to: range.upperBound).map(\.value)
        // 소급분이 없으면 열지 않는다. 다음 프레임에서 다시 시도한다 —
        // 여기서 파일을 만들면 **재생할 수 없는 0프레임 클립**이 남는다.
        guard let first = backlog.first else { return }

        // 이미 있는 이름은 건너뛴다. `ClipWriter.Session`은 덮어쓰지 않고
        // 거부하므로, 같은 초에 세션을 다시 시작해도 앞 세션의 클립이
        // 지워지지 않는다.
        var url: URL
        repeat {
            index += 1
            url = directory.appending(path: "\(stamp)-\(index).mov")
        } while FileManager.default.fileExists(atPath: url.path)

        let opened = try ClipWriter.Session(url: url, first: first)
        do {
            // 첫 프레임도 써야 한다 — `Session.init`은 크기와 원점만 정하고
            // 아무것도 쓰지 않는다.
            for frame in backlog { try opened.append(frame) }
        } catch {
            // 덜 쓰인 파일을 남기면 재생할 수 없는 `.mov`가 쌓인다.
            opened.cancel()
            throw error
        }
        session = opened
    }

    private func closeSession(_ segment: ClipPlanner.Segment) throws -> RecordedClip? {
        guard let open = session else { return nil }
        session = nil
        let written = try open.finish()
        return RecordedClip(written: written, segment: segment)
    }
}
