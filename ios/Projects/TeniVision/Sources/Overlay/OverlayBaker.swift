import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Vision

/// 사이드카를 굽다가 생긴 실패.
public enum OverlayBakeError: Error, Equatable {
    /// 영상에 비디오 트랙이 없다. 파일이 반쯤 쓰였을 수 있다.
    case noVideoTrack
    /// 트랙 크기가 0이다. 종횡비를 만들 수 없다.
    case invalidSize
    /// 읽기가 중간에 끊겼다.
    case readFailed(String)
    /// 사람을 찾은 프레임이 하나도 없다.
    ///
    /// **"실패"로 분류한다.** 빈 사이드카를 저장하면 리플레이가 "분석했고
    /// 사람이 없었다"를 "오버레이가 없다"와 구분할 수 없다.
    case noPoseFound
}

/// 클립 하나를 읽어 오버레이 사이드카를 굽는다.
///
/// ## 왜 오프라인인가
///
/// 리플레이를 열 때 계산하면 열 때마다 기다리고 배터리를 또 쓴다. 결과는
/// 클립당 결정적이므로 **한 번 계산해 사이드카에 둔다.**
///
/// ⚠️ **촬영 중에 돌리지 마라.** 라이브 포즈 추정과 CPU를 다투면 스윙
/// 트리거가 신호를 잃는다. 큐를 비우는 시점은 호출부가 정한다
/// (세션 종료 후).
///
/// ## 왜 `detectsHands`를 여기서만 켜는가
///
/// 라이브 `PoseEstimator`에 켜면 ADR-0006이 "라이브에 남는 분석은 스윙
/// 트리거용 포즈 하나"로 줄인 예산을 손 21관절로 되돌린다. 트리거는 손을
/// 쓰지 않는다. 오프라인은 예산 제약이 없다.
///
/// 근거: docs/07-기획/SPEC-0121-replay-overlay.md 선택지 2·6
public struct OverlayBaker: Sendable {

    /// 어깨를 믿을지 판단하는 임계. 라이브와 같은 값을 쓴다 — 다르면
    /// 오버레이가 트리거와 다른 사람을 그릴 수 있다.
    public let minimumConfidence: Double

    public init(minimumConfidence: Double = SwingTriggerProfile.default.minimumConfidence) {
        self.minimumConfidence = minimumConfidence
    }

    /// 클립 파일 하나를 끝까지 읽어 사이드카를 만든다.
    ///
    /// - Parameters:
    ///   - url: 클립 파일. 존재 확인은 호출부가 한다(`ClipLocator`).
    ///   - side: 라켓을 든 쪽.
    /// - Throws: `OverlayBakeError`
    public func bake(
        clipAt url: URL,
        side: RacketSide
    ) async throws -> OverlaySidecar {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw OverlayBakeError.noVideoTrack
        }
        let (naturalSize, transform, nominalFPS, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
        )

        // 플레이어는 `preferredTransform`을 적용해 보여준다. 오버레이가 그
        // 화면에 맞아야 하므로 **Vision에 방향을 넘겨 좌표까지 돌려받는다** —
        // 버퍼를 직접 돌리는 것보다 싸고, 뒤집기를 우리가 하지 않는다.
        let orientation = Self.orientation(from: transform)

        // ★ `naturalSize`가 아니라 **표시 크기**를 쓴다.
        //
        //   `AVPlayerLayer`가 레이아웃에 쓰는 것은 `presentationSize`이고,
        //   그것은 픽셀 종횡비(PAR)와 clean aperture를 적용한 값이다.
        //   `naturalSize`를 쓰면 비정방 픽셀 영상에서 **종횡비가 어긋나
        //   오버레이가 가로로 늘거나 줄어든다.** 같은 값이 라켓 추정의
        //   종횡비 보정에도 쓰이므로 두 곳이 함께 틀린다.
        //
        //   아이폰 녹화는 정방 픽셀이라 지금은 두 값이 같다. 그래도
        //   `naturalSize`를 믿지 않는다 — 같다는 것을 우리가 보장하지 않는다.
        let presentation = formats.first.map {
            CMVideoFormatDescriptionGetPresentationDimensions(
                $0, usePixelAspectRatio: true, useCleanAperture: true
            )
        } ?? naturalSize
        let displaySize = presentation.applying(transform)
        let width = abs(displaySize.width)
        let height = abs(displaySize.height)
        guard width > 0, height > 0 else { throw OverlayBakeError.invalidSize }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw OverlayBakeError.readFailed(reader.error?.localizedDescription ?? "시작 실패")
        }

        var request = DetectHumanBodyPoseRequest()
        // ★ 라켓 궤적이 손 관절을 쓴다. 이 한 줄이 없으면 `rightHand`가
        //   언제나 `nil`이고 라켓 레이어가 **아무 말 없이 비어 있다.**
        request.detectsHands = true

        let aspect = Double(width / height)
        var frames: [OverlayFrame] = []

        while let sample = output.copyNextSampleBuffer() {
            // ★ 취소를 확인한다. 없으면 클립 하나를 끝까지 굽고 나서야
            //   멈춘다 — 120fps 10초면 프레임 1200장이고, 그동안 CPU를
            //   붙든다. 앱이 백그라운드로 가도 계속 돈다.
            guard !Task.isCancelled else {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard pts.isFinite else { continue }

            let observations = try await request.perform(on: pixelBuffer, orientation: orientation)
            guard let chosen = PoseEstimator.primary(
                in: observations, minimumConfidence: minimumConfidence
            ) else { continue }

            if let frame = OverlayFrameBuilder.frame(
                from: chosen,
                side: side,
                aspect: aspect,
                // ★ **PTS를 그대로 담는다.** 첫 프레임을 0으로 당기지 않는다.
                //
                //   리플레이가 쓰는 시각은 `AVPlayer.currentTime()`이고 그것은
                //   에셋 타임라인 기준이다. 트랙의 첫 샘플이 0이 아닌 클립에서
                //   0으로 당기면 오버레이가 그 오프셋만큼 **통째로 밀린다** —
                //   영상과 어긋나지만 "조금 느린 것"처럼 보여 원인을 찾기 어렵다.
                //
                //   `Swing.startSeconds`도 같은 클립 기준 절대초다
                //   (`ReplayItem`). 세 값이 한 시계를 써야 한다.
                at: pts,
                minimumConfidence: minimumConfidence
            ) {
                frames.append(frame)
            }
        }

        if reader.status == .failed {
            throw OverlayBakeError.readFailed(reader.error?.localizedDescription ?? "읽기 실패")
        }
        guard !frames.isEmpty else { throw OverlayBakeError.noPoseFound }

        return OverlaySidecar(
            clipFileName: url.lastPathComponent,
            // 트랙의 `nominalFrameRate`를 쓴다. 발열로 강등된 클립은 이 값이
            // 세션의 fps와 다르다(ADR-0005) — 세션 값을 쓰면 어긋난다.
            frameRate: Double(nominalFPS),
            pixelWidth: Int(width.rounded()),
            pixelHeight: Int(height.rounded()),
            frames: frames
        )
    }

    /// `preferredTransform` → Vision에 넘길 방향.
    ///
    /// 90의 배수 네 가지만 다룬다. 촬영이 `videoRotationAngle`로 심는 값이
    /// 그것뿐이고(#82), 임의 각도는 `RenderTransform`도 지원하지 않는다.
    /// 모르는 변환은 `.up`으로 둔다 — **추측해 돌리면 오버레이가 통째로
    /// 어긋나고 그 원인을 찾기 어렵다.**
    static func orientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let a = transform.a.rounded()
        let b = transform.b.rounded()
        let c = transform.c.rounded()
        let d = transform.d.rounded()
        switch (a, b, c, d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
