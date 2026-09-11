import Foundation

/// 영상과 함께 저장하는 사이드카 메타데이터.
/// 0-C 오프라인 검증에서 이 값들이 필요하다.
/// 근거: docs/04-계획/WORK-PLAN.md 9.3절 0-A / 0-C
public struct ClipMetadata: Codable, Sendable {
    public let recordedAt: Date
    public let fileName: String

    // 요청값
    public let requestedFPS: Double
    public let requestedExposure: String

    // 실제 적용값 — 시스템이 요청을 거부하거나 조정할 수 있으므로 분리해 기록한다
    public let actualFPS: Double
    public let actualExposureSeconds: Double
    public let actualISO: Float

    // 촬영 조건
    public let distanceMeters: Double
    public let width: Int32
    public let height: Int32
    public let videoFieldOfView: Float
    public let isVideoBinned: Bool

    // 기기
    public let deviceModel: String
    public let systemVersion: String
    public let cameraType: String

    /// 이 조건에서 테니스공(6.7cm)의 예상 픽셀 지름.
    /// CAPTURE-PROTOCOL 5.1절 계산표를 실측으로 검증하는 값이므로 저장한다.
    public let estimatedBallPixelDiameter: Double

    /// `estimatedBallPixelDiameter`는 받지 않고 직접 계산한다.
    /// 호출자가 넘기게 두면 저장값이 BallGeometry와 어긋날 수 있다.
    public init(
        recordedAt: Date,
        fileName: String,
        requestedFPS: Double,
        requestedExposure: String,
        actualFPS: Double,
        actualExposureSeconds: Double,
        actualISO: Float,
        distanceMeters: Double,
        width: Int32,
        height: Int32,
        videoFieldOfView: Float,
        isVideoBinned: Bool,
        deviceModel: String,
        systemVersion: String,
        cameraType: String
    ) {
        self.recordedAt = recordedAt
        self.fileName = fileName
        self.requestedFPS = requestedFPS
        self.requestedExposure = requestedExposure
        self.actualFPS = actualFPS
        self.actualExposureSeconds = actualExposureSeconds
        self.actualISO = actualISO
        self.distanceMeters = distanceMeters
        self.width = width
        self.height = height
        self.videoFieldOfView = videoFieldOfView
        self.isVideoBinned = isVideoBinned
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.cameraType = cameraType
        self.estimatedBallPixelDiameter = BallGeometry.pixelDiameter(
            width: width,
            fieldOfView: videoFieldOfView,
            distanceMeters: distanceMeters
        )
    }

    public func write(besides movieURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let sidecar = movieURL.deletingPathExtension().appendingPathExtension("json")
        try encoder.encode(self).write(to: sidecar, options: .atomic)
    }
}
