import Foundation

/// 0-A의 핵심 산출물. 실기기에서 이 JSON을 내보내
/// docs/02-설계/CAPTURE-PROTOCOL.md 5.7절 "미결 사항"을 채운다.
public struct FormatReport: Codable, Sendable {
    public let generatedAt: Date
    public let device: DeviceInfo
    public let cameras: [CameraInfo]

    public struct DeviceInfo: Codable, Sendable {
        public let model: String          // 예: iPhone16,2
        public let systemName: String
        public let systemVersion: String
    }

    public struct CameraInfo: Codable, Sendable {
        public let deviceType: String     // builtInWideAngleCamera 등
        public let position: String       // back / front
        public let localizedName: String
        public let formats: [FormatInfo]
    }

    public struct FormatInfo: Codable, Sendable, Hashable {
        public let width: Int32
        public let height: Int32
        public let mediaSubType: String
        public let isVideoBinned: Bool
        public let minFrameRate: Double
        public let maxFrameRate: Double
        /// 계산값 검증에 쓰이는 실측 시야각 (도)
        public let videoFieldOfView: Float
        public let minExposureDurationSeconds: Double
        public let maxExposureDurationSeconds: Double
        public let minISO: Float
        public let maxISO: Float
        public let supportsVideoHDR: Bool
        public let maxZoomFactor: Double

        /// CAPTURE-PROTOCOL 5.1절 계산 검증용.
        /// 식은 BallGeometry 한 곳에만 둔다.
        public func ballPixelDiameter(atDistanceMeters d: Double) -> Double {
            BallGeometry.pixelDiameter(
                width: width, fieldOfView: videoFieldOfView, distanceMeters: d
            )
        }
    }
}
