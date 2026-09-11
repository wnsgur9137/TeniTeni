import AVFoundation
import UIKit

enum FormatInspector {

    @MainActor
    static func makeReport() -> FormatReport {
        FormatReport(
            generatedAt: Date(),
            device: deviceInfo(),
            cameras: discoverCameras().map(cameraInfo(for:))
        )
    }

    @MainActor
    private static func deviceInfo() -> FormatReport.DeviceInfo {
        let identifier = DeviceIdentifier.current
        let device = UIDevice.current
        return .init(
            model: identifier,
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }

    private static func discoverCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private static func cameraInfo(for device: AVCaptureDevice) -> FormatReport.CameraInfo {
        .init(
            deviceType: device.deviceType.rawValue,
            position: positionName(device.position),
            localizedName: device.localizedName,
            formats: device.formats.map(formatInfo(for:))
        )
    }

    private static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back: "back"
        case .front: "front"
        case .unspecified: "unspecified"
        @unknown default: "unknown"
        }
    }

    private static func formatInfo(for format: AVCaptureDevice.Format) -> FormatReport.FormatInfo {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let frameRates = format.videoSupportedFrameRateRanges
        let subType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        return .init(
            width: dims.width,
            height: dims.height,
            mediaSubType: fourCCString(subType),
            isVideoBinned: format.isVideoBinned,
            minFrameRate: frameRates.map(\.minFrameRate).min() ?? 0,
            maxFrameRate: frameRates.map(\.maxFrameRate).max() ?? 0,
            videoFieldOfView: format.videoFieldOfView,
            minExposureDurationSeconds: CMTimeGetSeconds(format.minExposureDuration),
            maxExposureDurationSeconds: CMTimeGetSeconds(format.maxExposureDuration),
            minISO: format.minISO,
            maxISO: format.maxISO,
            supportsVideoHDR: format.isVideoHDRSupported,
            maxZoomFactor: format.videoMaxZoomFactor
        )
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: (code >> 24) & 0xFF),
            UInt8(truncatingIfNeeded: (code >> 16) & 0xFF),
            UInt8(truncatingIfNeeded: (code >> 8) & 0xFF),
            UInt8(truncatingIfNeeded: code & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 리포트를 Documents에 JSON으로 저장하고 경로를 반환한다.
    static func export(_ report: FormatReport) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "formats_\(report.device.model)_\(formatter.string(from: report.generatedAt)).json"

        let url = URL.documentsDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}


/// utsname.machine 을 문자열로 읽는다 (예: iPhone16,2)
enum DeviceIdentifier {
    static var current: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let bytes = withUnsafeBytes(of: &sysinfo.machine) { Array($0) }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
