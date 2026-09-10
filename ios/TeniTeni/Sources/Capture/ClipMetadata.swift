import Foundation

/// 영상과 함께 저장하는 사이드카 메타데이터.
/// 0-C 오프라인 검증에서 이 값들이 필요하다.
/// 근거: docs/04-계획/WORK-PLAN.md 9.3절 0-A / 0-C
struct ClipMetadata: Codable, Sendable {
    let recordedAt: Date
    let fileName: String

    // 요청값
    let requestedFPS: Double
    let requestedExposure: String

    // 실제 적용값 — 시스템이 요청을 거부하거나 조정할 수 있으므로 분리해 기록한다
    let actualFPS: Double
    let actualExposureSeconds: Double
    let actualISO: Float

    // 촬영 조건
    let distanceMeters: Double
    let width: Int32
    let height: Int32
    let videoFieldOfView: Float
    let isVideoBinned: Bool

    // 기기
    let deviceModel: String
    let systemVersion: String
    let cameraType: String

    /// 이 조건에서 테니스공(6.7cm)의 예상 픽셀 지름.
    /// CAPTURE-PROTOCOL 5.1절 계산표를 실측으로 검증하는 값.
    var estimatedBallPixelDiameter: Double {
        guard videoFieldOfView > 0, distanceMeters > 0 else { return 0 }
        let halfFOV = Double(videoFieldOfView) * .pi / 180 / 2
        let frameWidthMeters = 2 * distanceMeters * tan(halfFOV)
        guard frameWidthMeters > 0 else { return 0 }
        return Double(width) * 0.067 / frameWidthMeters
    }

    func write(besides movieURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var payload = try JSONSerialization.jsonObject(with: try encoder.encode(self)) as? [String: Any] ?? [:]
        payload["estimatedBallPixelDiameter"] = estimatedBallPixelDiameter
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let sidecar = movieURL.deletingPathExtension().appendingPathExtension("json")
        try data.write(to: sidecar, options: .atomic)
    }
}
