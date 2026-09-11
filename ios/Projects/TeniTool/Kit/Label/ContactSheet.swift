import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 프레임들을 격자 PNG 한 장으로 뽑는다.
///
/// 터미널에 영상이 안 나오므로 사람이 볼 방법이 필요하다. 프레임마다
/// 창을 띄우면 120fps에서 훑기가 불가능하고, 시트는 한 장에 수십 프레임이
/// 들어가며 미리보기의 확대·스크롤을 공짜로 쓴다.
/// 근거: docs/07-기획/SPEC-0008-label-tool.md 구현 선택지 1
public struct ContactSheet: Sendable {

    public enum Failure: Error, CustomStringConvertible {
        case noVideoTrack
        case cannotGenerateImage(String)
        case cannotWritePNG

        public var description: String {
            switch self {
            case .noVideoTrack: "영상 트랙이 없습니다"
            case .cannotGenerateImage(let reason): "프레임을 추출할 수 없습니다: \(reason)"
            case .cannotWritePNG: "PNG를 쓸 수 없습니다"
            }
        }
    }

    public let columns: Int
    public let thumbnailWidth: Int
    /// 프레임 번호를 새기는 띠의 높이
    public let labelHeight: Int

    public init(columns: Int, thumbnailWidth: Int, labelHeight: Int = 28) {
        self.columns = columns
        self.thumbnailWidth = thumbnailWidth
        self.labelHeight = labelHeight
    }

    public struct Result: Sendable {
        public let frameNumbers: [Int]
        public let sheetSize: CGSize
        public let fps: Double
    }

    /// - Parameter frames: 뽑을 프레임 번호. 비어 있으면 아무것도 하지 않는다.
    public func render(
        videoURL: URL,
        frames: [Int],
        to output: URL
    ) async throws -> Result {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }
        let fps = Double(try await track.load(.nominalFrameRate))
        let natural = try await track.load(.naturalSize)

        // ★ AVAssetImageGenerator를 쓰지 않는다.
        // 시간으로 탐색하면 AVAssetReader와 다른 프레임이 나온다 — 실측으로
        // 약 6프레임 어긋났다. analyze가 AVAssetReader로 읽으므로 라벨과
        // 검출 결과가 다른 프레임 체계를 쓰게 되고, 그러면 임팩트 매칭이
        // 통째로 밀린다. 순차 읽기는 느리지만 오프라인 도구에서는 정확성이 우선이다.
        let wanted = Set(frames)
        let images = try extractFrames(asset: asset, track: track, wanted: wanted)

        let scale = Double(thumbnailWidth) / natural.width
        let thumbHeight = Int((natural.height * scale).rounded())
        let cellHeight = thumbHeight + labelHeight
        let rows = Int(ceil(Double(frames.count) / Double(columns)))

        let sheetWidth = columns * thumbnailWidth
        let sheetHeight = max(1, rows * cellHeight)

        guard let context = CGContext(
            data: nil,
            width: sheetWidth,
            height: sheetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.cannotWritePNG
        }

        context.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

        for (index, frame) in frames.enumerated() {
            guard let image = images[frame] else {
                throw Failure.cannotGenerateImage("프레임 \(frame)을 찾지 못했습니다")
            }

            let column = index % columns
            let row = index / columns
            // CGContext 원점은 좌하단이므로 행을 뒤집는다
            let originY = sheetHeight - (row + 1) * cellHeight

            context.draw(
                image,
                in: CGRect(
                    x: column * thumbnailWidth,
                    y: originY + labelHeight,
                    width: thumbnailWidth,
                    height: thumbHeight
                )
            )
            drawLabel(
                "\(frame)",
                in: context,
                at: CGPoint(x: Double(column * thumbnailWidth) + 6, y: Double(originY) + 7)
            )
        }

        guard let sheet = context.makeImage() else { throw Failure.cannotWritePNG }
        try write(sheet, to: output)

        return Result(
            frameNumbers: frames,
            sheetSize: CGSize(width: sheetWidth, height: sheetHeight),
            fps: fps
        )
    }

    /// 원하는 프레임만 순차 읽기로 뽑는다.
    ///
    /// `analyze`와 **같은 방식으로 프레임을 세야** 번호가 일치한다.
    /// 시간 기반 탐색(`AVAssetImageGenerator`)은 인코딩된 영상에서
    /// 다른 프레임을 준다.
    /// 테스트가 프레임 정확성을 검증하므로 internal로 둔다.
    func extractFrames(
        asset: AVAsset,
        track: AVAssetTrack,
        wanted: Set<Int>
    ) throws -> [Int: CGImage] {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw Failure.cannotGenerateImage(error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw Failure.cannotGenerateImage(reader.error?.localizedDescription ?? "startReading")
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        var images: [Int: CGImage] = [:]
        var frameIndex = 0
        let last = wanted.max() ?? 0

        while frameIndex <= last, let sample = output.copyNextSampleBuffer() {
            defer { frameIndex += 1 }
            guard wanted.contains(frameIndex),
                  let buffer = CMSampleBufferGetImageBuffer(sample)
            else { continue }

            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                throw Failure.cannotGenerateImage("프레임 \(frameIndex) 변환 실패")
            }
            images[frameIndex] = cgImage
        }
        reader.cancelReading()
        return images
    }

    /// 프레임 번호를 새긴다. **번호가 없으면 몇 번째인지 세야 하고,
    /// 그게 틀리면 라벨 전체가 어긋난다.**
    private func drawLabel(_ text: String, in context: CGContext, at point: CGPoint) {
        // NSAttributedString.Key는 AppKit에서 온다. CLI에 AppKit을 끌어올
        // 이유가 없으므로 Core Text 속성을 직접 쓴다.
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 15, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(
                red: 0.78, green: 0.95, blue: 0.31, alpha: 1
            ),
        ]
        guard let attributed = CFAttributedStringCreate(
            nil, text as CFString, attributes as CFDictionary
        ) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw Failure.cannotWritePNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.cannotWritePNG
        }
    }

    /// 훑을 프레임 번호를 고른다.
    ///
    /// - `around`가 있으면 그 주변을 **프레임 단위로** (정밀 확인)
    /// - 없으면 전체를 `stride` 간격으로 (대략 찾기)
    public static func frameNumbers(
        totalFrames: Int,
        around: Int?,
        span: Int,
        stride strideValue: Int
    ) -> [Int] {
        guard totalFrames > 0 else { return [] }
        if let around {
            let lower = max(0, around - span)
            let upper = min(totalFrames - 1, around + span)
            guard lower <= upper else { return [] }
            return Array(lower...upper)
        }
        return Swift.stride(from: 0, to: totalFrames, by: max(1, strideValue)).map { $0 }
    }
}
