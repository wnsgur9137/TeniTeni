import AVFoundation
import Foundation

public enum FormatInspector {

    /// 살아있는 캡처 기기를 훑어 보고서를 만든다.
    /// AVCaptureDevice.Format의 상세 속성 대부분이 macOS에 없으므로
    /// iOS에서만 제공한다. macOS CLI는 내보낸 JSON을 FormatReport로
    /// 디코딩해 읽는다 — 그쪽은 플랫폼 공용이다.
    #if os(iOS)
    public static func makeReport() -> FormatReport {
        FormatReport(
            generatedAt: Date(),
            device: deviceInfo(),
            cameras: discoverCameras().map(cameraInfo(for:))
        )
    }
    #endif

    /// UIDevice 대신 ProcessInfo를 쓴다. 양 플랫폼 공통 API라
    /// macOS CLI에서도 같은 코드가 동작한다 (SPEC-0005 구현 선택지 A).
    private static func deviceInfo() -> FormatReport.DeviceInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return .init(
            model: DeviceIdentifier.current,
            systemName: platformName,
            systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }

    private static var platformName: String {
        #if os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #else
        "unknown"
        #endif
    }

    #if os(iOS)
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

    #endif

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
    public static func export(_ report: FormatReport) throws -> URL {
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
public enum DeviceIdentifier {
    public static var current: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let bytes = withUnsafeBytes(of: &sysinfo.machine) { Array($0) }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
