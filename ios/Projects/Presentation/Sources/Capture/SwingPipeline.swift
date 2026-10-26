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

/// 포즈 한 장을 받아 스윙 구간을 클립과 세션으로 남긴다.
///
/// ## 순서는 누가 지키는가
///
/// **actor가 아니라 호출부가 지킨다.** `PoseAnalyzer.run`의 `for await`
/// 루프가 `await handle(...)`을 한 장씩 끝까지 기다리므로, 다음 프레임은
/// 앞 프레임의 처리가 끝난 뒤에 들어온다. 트리거는 순서에 의존하는 상태
/// 기계이고 그 보장이 여기서 나온다([동시성 6.1](../../../../../docs/02-설계/CONCURRENCY.md)).
///
/// actor인 이유는 다르다 — **녹화 시작·정지가 메인에서 들어온다.** 그 둘과
/// 프레임 처리가 같은 상태를 만지므로 보호가 필요하다. 재진입은 그 경로에서만
/// 일어나고, 그건 실제로 동시에 벌어지는 일이다.
///
/// 근거: docs/07-기획/SPEC-0097-swing-wiring.md
/// `ReadyFrame`이 내부 타입이므로 이 타입도 내부다 — 프레임은 카메라
/// 경계 밖으로 나가지 않는다.
actor SwingPipeline {

    /// 세션 하나가 쓰는 것들. 녹화가 시작되면 열리고 정지에서 닫힌다.
    private struct Active {
        var trigger: SwingTrigger
        let recorder: ClipRecorder<ReadyFrame>
        let builder: SessionBuilder
    }

    /// 녹화가 시작됐지만 아직 프레임이 오지 않은 상태. 세션 시계의 원점을
    /// **첫 프레임의 PTS**로 잡아야 하므로 그때까지 기다린다.
    private struct Pending {
        let startedAt: Date
        let handedness: Handedness
        let situation: CaptureSituation
        let observable: ObservationTarget
        let fps: Int
    }

    private let directory: URL
    private let storage: SessionStorage
    private let profile: SwingTriggerProfile

    private var pending: Pending?
    private var active: Active?

    /// 이번 세션에서 저장된 클립 수. 화면이 읽는다.
    private(set) var clipCount = 0
    /// 마지막 실패 사유. 조용히 삼키지 않는다.
    private(set) var failure: String?

    init(
        directory: URL = URL.documentsDirectory,
        storage: SessionStorage,
        profile: SwingTriggerProfile = .default
    ) {
        self.directory = directory
        self.storage = storage
        self.profile = profile
    }

    var isRecording: Bool { pending != nil || active != nil }

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
        clipCount = 0
        failure = nil
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
    func handle(_ frame: ReadyFrame, pose: PoseFrame?) async {
        if active == nil { open(at: frame.seconds) }
        guard var state = active else { return }

        do {
            if let clip = try await state.recorder.enqueue(frame) {
                await store(clip, in: state)
            }
            if let pose, let candidate = state.trigger.process(pose) {
                if let clip = try await state.recorder.accept(candidate) {
                    await store(clip, in: state)
                }
            }
            // `trigger`는 값 타입이다. 처리한 상태를 다시 넣지 않으면
            // 무장·교차가 매 프레임 초기화되어 **아무 스윙도 잡히지 않는다.**
            active = state
        } catch {
            failure = error.localizedDescription
        }
    }

    /// 녹화 정지. `postRoll`을 못 채운 마지막 스윙도 **가진 만큼** 저장하고,
    /// 스윙이 0개여도 세션을 남긴다 — 0개도 결과다.
    @discardableResult
    func end(at endedAt: Date) async -> Session? {
        defer {
            pending = nil
            active = nil
        }
        // 프레임이 한 장도 오지 않은 채 멈췄다. 남길 것이 없다.
        guard let state = active else { return nil }

        do {
            if let clip = try await state.recorder.finish() {
                await store(clip, in: state)
            }
        } catch {
            failure = error.localizedDescription
        }

        guard storage.repository != nil else {
            // 저장소가 없는 것은 이미 화면에 떠 있다(`SessionStorage.failure`).
            // 여기서 덮지 않는다 — 원인이 더 구체적인 쪽을 남긴다.
            return nil
        }
        do {
            return try await state.builder.finish(at: endedAt)
        } catch {
            failure = "세션 저장 실패: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - 내부

    /// 첫 프레임의 PTS를 원점으로 세션을 연다.
    private func open(at seconds: TimeInterval) {
        guard let pending, let repository = storage.repository else { return }
        let stamp = Self.stamp(for: pending.startedAt)
        active = Active(
            trigger: SwingTrigger(profile: profile, racketSide: pending.handedness.racketSide),
            recorder: ClipRecorder(
                profile: profile,
                directory: directory,
                stamp: stamp
            ),
            builder: SessionBuilder(
                startedAt: pending.startedAt,
                clockOrigin: seconds,
                situation: pending.situation,
                observable: pending.observable,
                fps: pending.fps,
                repository: repository
            )
        )
        self.pending = nil
    }

    private func store(_ clip: RecordedClip, in state: Active) async {
        await state.builder.add(clip)
        clipCount += 1
    }

    /// 파일명 접두사. 포매팅을 밖에 두면 테스트가 결정론적이다.
    static func stamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
