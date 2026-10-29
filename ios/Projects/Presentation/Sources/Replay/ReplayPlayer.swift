import AVFoundation
import Observation
import UIKit

/// `AVPlayer`를 들고 있는 쪽. **리듀서는 이 타입을 모른다.**
///
/// 촬영이 `CameraController`를 화면이 소유하게 둔 것과 같은 구조다
/// (`CaptureScreen`). 프레임·재생은 TCA 바깥으로 흐른다 — D-03 규칙.
@MainActor
@Observable
final class ReplayPlayer {

    let layer = AVPlayerLayer()

    /// 화면이 꽂는다. 플레이어가 올려보내는 것은 전부 이 세 개로 나간다.
    @ObservationIgnored var onTime: ((TimeInterval) -> Void)?
    @ObservationIgnored var onReachedEnd: (() -> Void)?
    @ObservationIgnored var onSlowMotionSupport: ((Bool) -> Void)?

    private let player = AVPlayer()

    /// 지금 물려 있는 파일. 같은 파일이 다시 오면 아이템을 갈지 않는다 —
    /// 같은 클립 안의 다음 스윙에서 재생이 끊기지 않게 한다.
    @ObservationIgnored private var loadedURL: URL?

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var boundaryObserver: Any?
    /// 구간 끝. 아이템이 준비되기 전에 지정될 수 있으므로 들고 있는다.
    @ObservationIgnored private var segmentEnd: TimeInterval?
    @ObservationIgnored private var pendingStart: TimeInterval?
    /// 화면이 바라는 재생 상태. **아이템이 준비된 뒤에 적용한다.**
    ///
    /// `AVPlayer`는 `.readyToPlay` 전에 준 `rate`를 보장하지 않는다.
    /// `automaticallyWaitsToMinimizeStalling`이 거짓이면 더 그렇다 — 그대로
    /// 두면 리플레이를 열었는데 아무것도 재생되지 않는다.
    @ObservationIgnored private var desired: (speed: PlaybackSpeed, playing: Bool) = (.standard, false)
    /// 탐색이 진행 중이다. 그동안 올라오는 시각은 버린다 — 스크러버를 끄는
    /// 동안 과거 위치가 올라와 엄지가 뒤로 튄다.
    @ObservationIgnored private var isSeeking = false

    init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        layer.player = player
        layer.videoGravity = .resizeAspect
        addPeriodicObserver()
    }

    // `deinit`에서 관측자를 떼지 않는다. 메인 액터 격리를 넘는 접근이 되고,
    // `player`가 함께 해제되므로 떼어낼 대상도 같이 사라진다. 화면이
    // 사라질 때 `unload()`가 부른다.

    private func addPeriodicObserver() {
        // 30Hz. 0.125×로 재생해도 스크러버가 부드럽게 따라온다.
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.onTime?(time.seconds)
            }
        }
    }

    // MARK: 적재

    func load(url: URL, startAt seconds: TimeInterval) {
        guard loadedURL != url else {
            Task { await seek(to: seconds) }
            return
        }
        loadedURL = url
        pendingStart = seconds

        let item = AVPlayerItem(
            asset: AVURLAsset(url: url),
            automaticallyLoadedAssetKeys: [.tracks, .duration]
        )
        // 상태 관측을 **아이템을 꽂기 전에** 건다. 플레이어에 붙는 순간이
        // 로딩 시작이라 그 뒤에 걸면 `.readyToPlay`를 놓칠 수 있다.
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.itemStatusChanged(item)
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        removeBoundaryObserver()
        loadedURL = nil
        segmentEnd = nil
        pendingStart = nil
        isSeeking = false
        desired = (.standard, false)
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            disableAudioTracks(of: item)
            onSlowMotionSupport?(item.canPlaySlowForward)
            installBoundaryObserver()
            if let pendingStart {
                self.pendingStart = nil
                Task { [weak self] in
                    await self?.seek(to: pendingStart)
                    // 탐색이 끝난 **뒤에** 재생을 건다. 먼저 걸면 시작점이
                    // 아니라 0초에서 재생이 터진다.
                    self?.applyDesired()
                }
            } else {
                applyDesired()
            }
        case .failed:
            // 파일 존재는 `ClipLocator`가 이미 걸렀다. 여기 오는 것은 손상된
            // 파일이므로 재생할 수 없다는 사실만 올려보낸다.
            onSlowMotionSupport?(false)
        default:
            break
        }
    }

    /// 오디오 트랙을 끈다.
    ///
    /// `step(byCount:)`의 스텝 크기는 **활성 트랙**이 정한다. 마이크 권한이
    /// 있으면 클립에 오디오가 들어가므로(`CapturePermissionPlan`), 켜 둔 채로
    /// 스텝하면 한 비디오 프레임이라는 보장이 없다.
    ///
    /// 0.125×로 재생하는 오디오가 소음이라는 이유도 같은 방향이다.
    private func disableAudioTracks(of item: AVPlayerItem) {
        for track in item.tracks where track.assetTrack?.mediaType == .audio {
            track.isEnabled = false
        }
    }

    // MARK: 구간

    func setSegment(end seconds: TimeInterval) {
        // 끝이 그대로면 다시 걸지 않는다. 스크러버를 끄는 동안 `seek`가
        // 수십 번 오는데, 그때마다 관측자를 떼고 다시 거는 것은 낭비다.
        guard segmentEnd != seconds || boundaryObserver == nil else { return }
        segmentEnd = seconds
        installBoundaryObserver()
    }

    private func installBoundaryObserver() {
        removeBoundaryObserver()
        guard let segmentEnd, player.currentItem?.status == .readyToPlay else { return }
        let time = CMTime(seconds: segmentEnd, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time)],
            queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated { self?.onReachedEnd?() }
        }
    }

    private func removeBoundaryObserver() {
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
    }

    // MARK: 재생

    func apply(speed: PlaybackSpeed, playing: Bool) {
        desired = (speed, playing)
        // 멈추는 것은 언제든 즉시 먹힌다. 재생은 준비된 뒤여야 한다.
        guard !playing || player.currentItem?.status == .readyToPlay else {
            if !playing { player.pause() }
            return
        }
        applyDesired()
    }

    private func applyDesired() {
        guard player.currentItem != nil else { return }
        if desired.playing {
            player.rate = Float(desired.speed.rawValue)
        } else {
            player.pause()
        }
    }

    /// 정밀 탐색. 관용값을 주면 반복할 때마다 시작점이 흔들린다.
    func seek(to seconds: TimeInterval) async {
        guard player.currentItem != nil else { return }
        isSeeking = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        isSeeking = false
    }

    func step(by count: Int) {
        guard let item = player.currentItem else { return }
        player.pause()
        if count > 0, !item.canStepForward { return }
        if count < 0, !item.canStepBackward { return }
        item.step(byCount: count)
    }
}
