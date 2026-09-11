import AVFoundation

// 살아있는 캡처 기기의 포맷을 고르는 일이므로 iOS 전용이다.
// Format.isVideoBinned가 macOS에 없고, 0-C macOS CLI는 이미 찍힌
// 영상을 다루므로 이 타입을 필요로 하지 않는다.
#if os(iOS)

/// AVCaptureSession.Preset은 프레임레이트를 표현하지 못하므로 activeFormat을 직접 고른다.
/// 근거: docs/02-설계/CAPTURE-PROTOCOL.md 5.2절
public enum FormatSelector {

    /// 목표 fps와 폭을 만족하는 포맷을 고른다.
    /// 같은 조건이면 binned가 아닌(실효 해상도가 높은) 쪽을 우선한다.
    public static func format(
        in device: AVCaptureDevice,
        targetFPS: Double,
        width: Int32 = 1920
    ) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == width else { return false }
            return format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= targetFPS
            }
        }
        // binned가 아닌 포맷 우선
        return candidates.first { !$0.isVideoBinned } ?? candidates.first
    }

    /// 기기가 해당 fps를 지원하는지
    public static func supports(_ device: AVCaptureDevice, fps: Double, width: Int32 = 1920) -> Bool {
        format(in: device, targetFPS: fps, width: width) != nil
    }
}
#endif
