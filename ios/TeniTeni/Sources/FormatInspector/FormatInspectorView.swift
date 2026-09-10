import SwiftUI

/// 0-A의 핵심 산출물 화면. 지원 포맷을 열거하고 JSON으로 내보낸다.
struct FormatInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: FormatReport?
    @State private var exportedURL: URL?
    @State private var error: String?
    /// CAPTURE-PROTOCOL 5.1절 계산표를 실측으로 검증하기 위한 거리
    @State private var distance: Double = 6

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    content(report)
                } else if let error {
                    ContentUnavailableView("포맷을 읽을 수 없습니다", systemImage: "xmark.octagon", description: Text(error))
                } else {
                    ProgressView("포맷 수집 중…")
                }
            }
            .navigationTitle("지원 포맷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let url = exportedURL {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    } else {
                        Button("내보내기", action: export)
                    }
                }
            }
        }
        .task { report = FormatInspector.makeReport() }
    }

    private func content(_ report: FormatReport) -> some View {
        List {
            Section("기기") {
                row("모델", report.device.model)
                row("OS", "\(report.device.systemName) \(report.device.systemVersion)")
            }

            Section {
                Picker("거리", selection: $distance) {
                    Text("5m").tag(5.0)
                    Text("6m").tag(6.0)
                    Text("8m").tag(8.0)
                    Text("10m").tag(10.0)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("공 크기 계산 거리")
            } footer: {
                Text("각 포맷에서 테니스공(6.7cm)이 몇 픽셀로 보이는지 계산합니다. 8px 미만이면 궤적 검출이 어렵습니다.")
            }

            ForEach(report.cameras, id: \.deviceType) { camera in
                Section("\(camera.localizedName) · \(camera.position)") {
                    ForEach(highFrameRateFirst(camera.formats), id: \.self) { format in
                        formatRow(format)
                    }
                }
            }
        }
    }

    /// 120fps 이상을 지원하는 1080p 포맷을 위로 올린다. 우리가 쓸 포맷이다.
    private func highFrameRateFirst(_ formats: [FormatReport.FormatInfo]) -> [FormatReport.FormatInfo] {
        formats.sorted { lhs, rhs in
            let lhsPriority = (lhs.width == 1920 && lhs.maxFrameRate >= 120) ? 0 : 1
            let rhsPriority = (rhs.width == 1920 && rhs.maxFrameRate >= 120) ? 0 : 1
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.maxFrameRate > rhs.maxFrameRate
        }
    }

    private func formatRow(_ format: FormatReport.FormatInfo) -> some View {
        let ballPx = format.ballPixelDiameter(atDistanceMeters: distance)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(format.width)×\(format.height)").bold()
                Text("· \(Int(format.maxFrameRate))fps")
                if format.isVideoBinned {
                    Text("binned").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text(String(format: "공 %.1fpx", ballPx))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ballPx >= 12 ? .green : ballPx >= 8 ? .orange : .red)
            }
            Text("화각 \(String(format: "%.1f", format.videoFieldOfView))° · 노출 \(exposureRange(format)) · ISO \(Int(format.minISO))–\(Int(format.maxISO))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func exposureRange(_ format: FormatReport.FormatInfo) -> String {
        let minText = format.minExposureDurationSeconds > 0
            ? "1/\(Int((1 / format.minExposureDurationSeconds).rounded()))"
            : "-"
        return "\(minText)~"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }

    private func export() {
        guard let report else { return }
        do {
            exportedURL = try FormatInspector.export(report)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
