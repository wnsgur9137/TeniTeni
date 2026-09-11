import Foundation

/// 0-A의 핵심 산출물. 실기기에서 이 JSON을 내보내
/// docs/02-설계/CAPTURE-PROTOCOL.md 5.7절 "미결 사항"을 채운다.
struct FormatReport: Codable, Sendable {
    let generatedAt: Date
    let device: DeviceInfo
    let cameras: [CameraInfo]

    struct DeviceInfo: Codable, Sendable {
        let model: String          // 예: iPhone16,2
        let systemName: String
        let systemVersion: String
    }

    struct CameraInfo: Codable, Sendable {
        let deviceType: String     // builtInWideAngleCamera 등
        let position: String       // back / front
        let localizedName: String
        let formats: [FormatInfo]
    }

    struct FormatInfo: Codable, Sendable, Hashable {
        let width: Int32
        let height: Int32
        let mediaSubType: String
        let isVideoBinned: Bool
        let minFrameRate: Double
        let maxFrameRate: Double
        /// 계산값 검증에 쓰이는 실측 시야각 (도)
        let videoFieldOfView: Float
        let minExposureDurationSeconds: Double
        let maxExposureDurationSeconds: Double
        let minISO: Float
        let maxISO: Float
        let supportsVideoHDR: Bool
        let maxZoomFactor: Double

        /// CAPTURE-PROTOCOL 5.1절 계산 검증용:
        /// 이 시야각에서 거리 d일 때 테니스공(6.7cm)이 몇 px로 보이는가
        func ballPixelDiameter(atDistanceMeters d: Double) -> Double {
            guard videoFieldOfView > 0, d > 0 else { return 0 }
            let halfFOV = Double(videoFieldOfView) * .pi / 180 / 2
            let frameWidthMeters = 2 * d * tan(halfFOV)
            guard frameWidthMeters > 0 else { return 0 }
            return Double(width) * 0.067 / frameWidthMeters
        }
    }
}
