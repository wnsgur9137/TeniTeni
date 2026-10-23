import Foundation

/// 쓰기를 마친 클립 하나. 도메인 엔티티로 옮기기 직전의 형태다.
///
/// `TeniVision`은 `Domain`을 모른다(계층 구조상 의존성 0). 그래서 여기서
/// `Clip`을 만들지 않고, 둘을 함께 아는 계층이 옮긴다.
public struct RecordedClip: Sendable, Equatable {
    public let url: URL
    /// 첫 프레임의 **프레임 시계** 값. 영상의 PTS 0이 이 시각이다.
    ///
    /// 벽시계가 아니다 — 카메라가 배선되면
    /// `CMSampleBuffer.presentationTimeStamp`, 즉 부팅 이후 호스트 시각이
    /// 된다. 날짜로 바꾸려면 **세션 시작 시점의 프레임 시계 값을 빼야
    /// 한다**(`SessionBuilder`의 `clockOrigin`).
    public let startedAt: TimeInterval
    /// 첫 프레임부터 마지막 프레임까지의 간격.
    public let duration: TimeInterval
    public let frameCount: Int
    /// 클립 시작 기준 **상대초**로 바뀐 스윙들.
    public let swings: [RecordedSwing]

    public init(
        url: URL,
        startedAt: TimeInterval,
        duration: TimeInterval,
        frameCount: Int,
        swings: [RecordedSwing]
    ) {
        self.url = url
        self.startedAt = startedAt
        self.duration = duration
        self.frameCount = frameCount
        self.swings = swings
    }

    /// 쓰기 결과와 구간을 합친다.
    ///
    /// ## 왜 절대 시각을 쓰지 않는가
    ///
    /// 세션 시계는 `AVCaptureSession`이 주는 값이고 앱 실행마다 다르다.
    /// 클립 하나를 재생할 때 필요한 것은 **그 클립 안에서 몇 초인가**다.
    /// 원점은 구간의 하한이 아니라 **실제로 쓰인 첫 프레임**이다 — 세션
    /// 시작 직후면 하한보다 늦을 수 있고, PTS 0은 그 프레임이다.
    public init(written: ClipWriter.Written, segment: ClipPlanner.Segment) {
        let origin = written.startedAt
        let duration = written.duration
        func relative(_ absolute: TimeInterval) -> TimeInterval {
            min(max(0, absolute - origin), duration)
        }
        self.init(
            url: written.url,
            startedAt: origin,
            duration: duration,
            frameCount: written.frameCount,
            swings: segment.marks.map { mark in
                RecordedSwing(
                    startSeconds: relative(mark.start),
                    impactSeconds: relative(mark.triggeredAt),
                    endSeconds: relative(mark.end),
                    peakAngularVelocity: mark.peakAngularVelocity
                )
            }
        )
    }
}

/// 클립 안의 스윙 하나. 전부 **클립 시작 기준 상대초**다.
public struct RecordedSwing: Sendable, Equatable {
    public let startSeconds: TimeInterval
    /// 손목이 몸통선을 교차한 시점. 임팩트의 근사다 — 분류(1-D)가
    /// 정밀화한다.
    public let impactSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let peakAngularVelocity: Double

    public init(
        startSeconds: TimeInterval,
        impactSeconds: TimeInterval,
        endSeconds: TimeInterval,
        peakAngularVelocity: Double
    ) {
        self.startSeconds = startSeconds
        self.impactSeconds = impactSeconds
        self.endSeconds = endSeconds
        self.peakAngularVelocity = peakAngularVelocity
    }
}
