import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// 분석 입력을 줄인다. 1080p를 그대로 Vision에 넣으면 프레임 예산을 넘는다 —
/// [비전 파이프라인 3.7](../../../../../docs/02-설계/VISION-PIPELINE.md)이
/// "분석 입력은 반드시 다운스케일한다"를 정했다.
///
/// ## 왜 사본을 만드는가
///
/// 성능만의 문제가 아니다. `CVReadOnlyPixelBuffer.withUnsafeBuffer(_:)`가
/// 내주는 버퍼는 **그 동기 클로저 안에서만** 유효한데, Vision의
/// `perform(on:)`은 `async`다. 목적지 버퍼는 우리가 만든 것이므로 그 수명을
/// 우리가 안다 — `await`를 넘어가도 된다.
///
/// ## 왜 letterbox인가
///
/// 종횡비를 바꾸면 관절 좌표가 눌려 각도가 틀어진다. 목표 크기를 원본
/// 비율에서 뽑으므로 보통은 여백이 생기지 않고, 비율이 다른 포맷이 와도
/// 늘리지 않고 여백을 둔다. 균일 축소와 평행이동은 몸통 기준 기하를
/// 바꾸지 않는다.
///
/// ## 왜 Sendable이 아닌가
///
/// 전송 세션과 버퍼 풀을 들고 있고, 이 둘은 공유하면 안 된다. 포즈를 돌리는
/// **단일 Task 안에서 만들어 그 안에서만 쓴다** — 격리를 타입으로 좁히는
/// 쪽이 actor로 감싸 재진입을 허용하는 쪽보다 낫다([동시성 6.1](../../../../../docs/02-설계/CONCURRENCY.md)).
///
/// 근거: docs/07-기획/SPEC-0096-pose-intake.md 구현 선택지 1
final class FrameDownscaler {

    enum Failure: Error, Equatable {
        case cannotCreateSession(OSStatus)
        case cannotCreatePool(OSStatus)
        case cannotCreateBuffer(OSStatus)
        case transferFailed(OSStatus)
        case emptyDimensions
    }

    /// 긴 변의 목표 길이. 640×360이면 포즈 추정이 3~5ms로 예산에 들어간다.
    let longEdge: Int

    private var session: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolTarget: CMVideoDimensions?

    init(longEdge: Int = 640) {
        self.longEdge = longEdge
    }

    /// 원본 비율을 유지한 목표 크기. 두 변 모두 짝수로 맞춘다 —
    /// 4:2:0 크로마 서브샘플링은 홀수 크기를 좋아하지 않는다.
    ///
    /// 원본이 목표보다 작으면 **키우지 않는다.** 없는 디테일을 만들어도
    /// 검출이 좋아지지 않고 비용만 는다.
    func target(for source: CMVideoDimensions) -> CMVideoDimensions {
        let width = Int(source.width)
        let height = Int(source.height)
        guard width > 0, height > 0 else { return source }

        let long = max(width, height)
        guard long > longEdge else { return CMVideoDimensions(width: Int32(even(width)), height: Int32(even(height))) }

        let scale = Double(longEdge) / Double(long)
        return CMVideoDimensions(
            width: Int32(even(Int((Double(width) * scale).rounded()))),
            height: Int32(even(Int((Double(height) * scale).rounded())))
        )
    }

    /// 목적지 버퍼를 **빌리기 전에** 만든다. 풀은 목표 크기가 바뀔 때만 다시 세운다.
    func makeDestination(for source: CMVideoDimensions) throws -> CVPixelBuffer {
        let size = target(for: source)
        guard size.width > 0, size.height > 0 else { throw Failure.emptyDimensions }

        // `CMVideoDimensions`는 Equatable이 아니다 — 두 변을 직접 본다.
        let sameTarget = poolTarget.map { $0.width == size.width && $0.height == size.height } ?? false
        if !sameTarget || pool == nil {
            pool = try makePool(size)
            poolTarget = size
        }
        guard let pool else { throw Failure.cannotCreatePool(kCVReturnError) }

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw Failure.cannotCreateBuffer(status)
        }
        return buffer
    }

    /// 빌린 원본을 목적지로 전송한다. 동기로 끝나므로 빌림 범위를 벗어나지 않는다.
    func transfer(from source: CVPixelBuffer, to destination: CVPixelBuffer) throws {
        let session = try transferSession()
        let status = VTPixelTransferSessionTransferImage(session, from: source, to: destination)
        guard status == noErr else { throw Failure.transferFailed(status) }
    }

    // MARK: - 자원

    private func transferSession() throws -> VTPixelTransferSession {
        if let session { return session }
        var created: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &created)
        guard status == noErr, let created else { throw Failure.cannotCreateSession(status) }
        // 늘리지 않는다 — 종횡비가 바뀌면 각도가 틀어진다.
        VTSessionSetProperty(
            created,
            key: kVTPixelTransferPropertyKey_ScalingMode,
            value: kVTScalingMode_Letterbox
        )
        session = created
        return created
    }

    private func makePool(_ size: CMVideoDimensions) throws -> CVPixelBufferPool {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            // Metal·Vision이 같은 IOSurface를 보도록 둔다. 없으면 복사가 한 번 더 생긴다.
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var created: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
        guard status == kCVReturnSuccess, let created else { throw Failure.cannotCreatePool(status) }
        return created
    }

    private func even(_ value: Int) -> Int { value - (value % 2) }
}
