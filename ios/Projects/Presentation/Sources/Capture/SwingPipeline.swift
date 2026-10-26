import Domain
import Foundation
import TeniVision

/// 주 사용 손을 라켓 쪽으로 옮긴다.
///
/// `TeniVision`은 `Domain`을 모른다(`Project.swift`). 변환은 둘을 함께 아는
/// 가장 낮은 계층인 여기서 한다 — [아키텍처 2.2](../../../../../docs/02-설계/ARCHITECTURE.md).
extension Handedness {
    var racketSide: RacketSide {
        switch self {
        case .right: .right
        case .left: .left
        }
    }
}

/// 상황에 맞는 트리거 프로파일.
///
/// 벽치기는 **기본값을 쓰면 통째로 놓친다** — 벽이 가까워 스윙이 구조적으로
/// 짧고 느리다(`SwingTriggerProfile.wall`의 근거). 상황을 받아 놓고 쓰지
/// 않으면 `.wall`로 촬영한 사용자는 스윙 0개를 보고 원인을 알 수 없다.
extension CaptureSituation {
    var triggerProfile: SwingTriggerProfile {
        switch self {
        case .wall: .wall
        case .ballMachine, .rally, .match, .lesson: .default
        }
    }
}

/// 소급분으로 들고 있을 장 수 상한.
///
/// ## 이 숫자는 잠정값이다
///
/// `AVCaptureVideoDataOutput`은 풀 크기를 공개하지 않는다. 실기기에서
/// 드롭 수를 보며 올려야 하고(#103), 그 측정 없이는 "안전한 최대"를 알 수
/// 없다. 그래서 **의심스러울 때 작은 쪽**으로 둔다 — 상한이 작으면 클립의
/// 머리가 잘리지만, 크면 분석이 통째로 끊긴다. 둘의 대가가 다르다.
///
/// 24장 = 분석 60fps 기준 **0.4초**다. 기본 `preRoll`(2초)보다 훨씬 짧으므로
/// 클립에서 테이크백 대부분이 빠진다 — 이것은 **임시 타협**이고, 소급분을
/// 캡처 풀 밖으로 옮기는 설계(#103)가 회복한다.
///
/// 잘린 장 수는 세어 화면에 올린다. 조용히 짧아지지 않게 한다.
private let backlogFrameCapacity = 24

/// 파이프라인이 한 프레임을 처리한 결과. 화면이 읽는 값만 담는다.
///
/// 프레임마다 actor를 세 번 찾아가는(처리·카운트·실패) 대신 **한 번에 받아
/// 온다.** 60fps면 그 차이가 초당 홉 120회다.
struct SwingSnapshot: Sendable, Equatable {
    /// 트리거가 발화한 횟수. **클립 수가 아니다** — `ClipPlanner`가 겹치는
    /// 후보를 한 클립으로 병합하므로 랠리 20번이 클립 1~2개가 된다.
    let swingCount: Int
    /// 저장된 클립 수.
    let clipCount: Int
    let failure: String?
    /// 상한에 걸려 버린 소급 프레임 수. 0이 아니면 클립의 머리가 잘린다.
    let droppedBacklog: Int
    /// 이 결과가 가리키는 프레임 시각. 늦게 도착한 과거 스냅샷을 걸러낸다.
    let seconds: TimeInterval
}

/// 포즈 한 장을 받아 스윙 구간을 클립과 세션으로 남긴다.
///
/// ## 순서는 누가 지키는가
///
/// **actor가 아니라 호출부가 지킨다.** `PoseAnalyzer.run`의 `for await`
/// 루프가 `await handle(...)`을 한 장씩 끝까지 기다리므로, 다음 프레임은
/// 앞 프레임의 처리가 끝난 뒤에 들어온다. 트리거는 순서에 의존하는 상태
/// 기계이고 그 보장이 여기서 나온다([동시성 6.1](../../../../../docs/02-설계/CONCURRENCY.md)).
///
/// ## 재진입을 어떻게 다루는가
///
/// 녹화 시작·정지는 메인에서 들어오므로 `handle`의 `await` 사이에 끼어든다.
/// 그것은 실제로 동시에 벌어지는 일이라 막을 수 없다. 대신 **세대 토큰**을
/// 둔다 — `begin`·`end`가 세대를 올리고, `handle`은 재개할 때 세대가
/// 바뀌었으면 쓰기를 포기한다.
///
/// 토큰이 없으면 `end()`가 닫은 세션이 `handle`의 뒤늦은 쓰기로 **되살아나고**,
/// 그 뒤의 모든 녹화가 첫 세션 id로 덮여 레코드가 사라진다.
///
/// 트리거 상태는 `await` 없이 제자리에서 바꾼다(`processTrigger`) — 꺼내
/// 되돌려 넣는 사이에 끼어들 틈을 만들지 않는다.
///
/// 근거: docs/07-기획/SPEC-0097-swing-wiring.md
actor SwingPipeline {

    private let directory: URL
    private let storage: SessionStorage

    // MARK: 세션 상태

    /// 녹화가 시작됐지만 아직 프레임이 오지 않았다. 세션 시계의 원점을
    /// **첫 프레임의 PTS**로 잡아야 하므로 그때까지 기다린다.
    private struct Pending {
        let startedAt: Date
        let handedness: Handedness
        let situation: CaptureSituation
        let observable: ObservationTarget
        let fps: Int
    }

    private var pending: Pending?
    private var trigger: SwingTrigger?
    private var recorder: ClipRecorder<ReadyFrame>?
    /// 저장소가 없으면 `nil`이다. 그래도 **클립 파일은 쓴다** — 디스크에
    /// 남은 `.mov`는 나중에 복구할 수 있는 자산이고, 안 만들면 그조차 없다.
    private var builder: SessionBuilder?

    /// `begin`·`end`가 올린다. `handle`이 재개할 때 이 값이 바뀌었으면
    /// 그 세션은 이미 끝난 것이므로 아무것도 쓰지 않는다.
    private var generation = 0

    private(set) var swingCount = 0
    private(set) var clipCount = 0
    private(set) var failure: String?
    /// 쓰기가 한 번 깨지면 매 프레임 같은 오류가 반복된다. 멈춘다.
    private var writesDisabled = false

    init(directory: URL = URL.documentsDirectory, storage: SessionStorage) {
        self.directory = directory
        self.storage = storage
    }

    var isRecording: Bool { pending != nil || recorder != nil }

    /// 녹화 시작. **여기서 세션을 만들지 않는다** — 프레임 시계의 원점을
    /// 아직 모른다. 첫 프레임에서 만든다.
    func begin(
        at startedAt: Date,
        handedness: Handedness,
        situation: CaptureSituation,
        observable: ObservationTarget,
        fps: Int
    ) {
        guard !isRecording else { return }
        generation += 1
        swingCount = 0
        clipCount = 0
        failure = nil
        writesDisabled = false
        pending = Pending(
            startedAt: startedAt,
            handedness: handedness,
            situation: situation,
            observable: observable,
            fps: fps
        )
    }

    /// 프레임 하나를 흘린다. 포즈가 없는 프레임도 버퍼에는 담는다 —
    /// 사람이 잠깐 가려진 구간이 클립에서 잘리면 임팩트가 사라진다.
    @discardableResult
    func handle(_ frame: ReadyFrame, pose: PoseFrame?) async -> SwingSnapshot {
        if recorder == nil { open(at: frame.seconds) }
        guard let recorder, !writesDisabled else { return snapshot(at: frame.seconds) }

        let token = generation
        do {
            if let clip = try await recorder.enqueue(frame) {
                droppedBacklog = await recorder.droppedBacklogCount
                guard token == generation else { return snapshot(at: frame.seconds) }
                await store(clip, token: token)
            }
            // 트리거는 `await` 없이 제자리에서 돌린다 — 꺼내 되돌려 넣는
            // 사이에 `end()`가 끼면 그 프레임의 진행분이 사라진다.
            if let pose, let candidate = processTrigger(pose) {
                swingCount += 1

                if let clip = try await recorder.accept(candidate) {
                    guard token == generation else { return snapshot(at: frame.seconds) }
                    await store(clip, token: token)
                }
            }
        } catch {
            // 한 번 깨진 쓰기는 매 프레임 같은 오류를 낸다. 세우고 사유를 남긴다.
            writesDisabled = true
            failure = "클립 쓰기 실패: \(error.localizedDescription)"
        }
        return snapshot(at: frame.seconds)
    }

    /// 녹화 정지. `postRoll`을 못 채운 마지막 스윙도 **가진 만큼** 저장하고,
    /// 스윙이 0개여도 세션을 남긴다 — 0개도 결과다.
    ///
    /// 두 번 불려도 안전하다. 백그라운드 진입과 녹화 델리게이트가 **둘 다**
    /// 이 경로로 들어온다.
    @discardableResult
    func end(at endedAt: Date) async -> Session? {
        guard isRecording else { return nil }
        generation += 1
        let token = generation
        let closing = (recorder: recorder, builder: builder)
        pending = nil
        recorder = nil
        builder = nil
        trigger = nil

        guard let recorder = closing.recorder else { return nil }
        droppedBacklog = await recorder.droppedBacklogCount

        if !writesDisabled {
            do {
                if let clip = try await recorder.finish() {
                    if let builder = closing.builder, token == generation {
                        await builder.add(clip)
                        clipCount += clip.swings.count
                    }
                }
            } catch {
                failure = "마지막 클립 저장 실패: \(error.localizedDescription)"
            }
        }

        guard let builder = closing.builder else { return nil }
        do {
            return try await builder.finish(at: endedAt)
        } catch {
            failure = "세션 저장 실패: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 내부

    /// 첫 프레임의 PTS를 원점으로 세션을 연다.
    ///
    /// 저장소가 없어도 **레코더는 만든다.** 클립 파일은 디스크에 남아
    /// 복구할 수 있지만, 안 만들면 그조차 없다.
    private func open(at seconds: TimeInterval) {
        guard let pending else { return }
        let profile = pending.situation.triggerProfile
        trigger = SwingTrigger(profile: profile, racketSide: pending.handedness.racketSide)
        recorder = ClipRecorder(
            profile: profile,
            directory: directory,
            stamp: Self.stamp(for: pending.startedAt),
            // 소급분이 캡처 풀을 붙든다. 상한 없이는 풀이 고갈돼
            // 분석이 끊긴다 — #103.
            backlogCapacity: backlogFrameCapacity
        )
        if let repository = storage.repository {
            builder = SessionBuilder(
                startedAt: pending.startedAt,
                clockOrigin: seconds,
                situation: pending.situation,
                observable: pending.observable,
                fps: pending.fps,
                repository: repository
            )
        }
        self.pending = nil
    }

    /// `await`가 없다. 그래서 그 사이에 `end()`가 끼어들 틈이 없다.
    private func processTrigger(_ pose: PoseFrame) -> SwingCandidate? {
        guard var trigger else { return nil }
        let candidate = trigger.process(pose)
        self.trigger = trigger
        return candidate
    }

    private func store(_ clip: RecordedClip, token: Int) async {
        guard let builder else { return }
        await builder.add(clip)
        // 돌아왔을 때 세션이 바뀌었으면 셈하지 않는다 — 닫힌 세션의 클립이
        // 다음 녹화의 수치에 섞인다.
        guard token == generation else { return }
        clipCount += clip.swings.count
    }

    private func snapshot(at seconds: TimeInterval) -> SwingSnapshot {
        SwingSnapshot(
            swingCount: swingCount,
            clipCount: clipCount,
            failure: failure,
            droppedBacklog: droppedBacklog,
            seconds: seconds
        )
    }

    /// 상한에 걸려 버린 소급 프레임 수. 레코더가 사라진 뒤에도 마지막
    /// 값을 들고 있어야 화면이 그 사실을 계속 보여줄 수 있다.
    private(set) var droppedBacklog = 0

    /// 파일명 접두사. 포매팅을 밖에 두면 테스트가 결정론적이다.
    static func stamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
