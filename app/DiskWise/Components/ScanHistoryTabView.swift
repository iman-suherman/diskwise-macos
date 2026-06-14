import DatabaseKit
import DiskScannerKit
import SwiftUI

struct ScanHistoryTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                schedulerSection
                historySection
            }
            .padding(.bottom, 28)
        }
        .onAppear {
            viewModel.refreshScanHistory()
            viewModel.reloadVolumeScanSchedule()
        }
    }

    @ViewBuilder
    private var schedulerSection: some View {
        if viewModel.selectedVolume != nil {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Scheduled scans", systemImage: "calendar.badge.clock")
                        .font(.headline)

                    Text("DiskWise can run fast and deep scans automatically when your Mac is usually idle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    recommendationCallout

                    scheduleRow(
                        title: "Fast scan",
                        icon: "bolt.fill",
                        summary: ScanScheduleAdvisor.fastScanSummary(for: viewModel.volumeScanSchedule),
                        rationale: ScanScheduleAdvisor.fastScanRationale(),
                        isOn: Binding(
                            get: { viewModel.volumeScanSchedule.fastScanEnabled },
                            set: { viewModel.setFastScanScheduleEnabled($0) }
                        )
                    )

                    scheduleRow(
                        title: "Deep scan",
                        icon: "scope",
                        summary: ScanScheduleAdvisor.deepScanSummary(for: viewModel.volumeScanSchedule),
                        rationale: ScanScheduleAdvisor.deepScanRationale(),
                        isOn: Binding(
                            get: { viewModel.volumeScanSchedule.deepScanEnabled },
                            set: { viewModel.setDeepScanScheduleEnabled($0) }
                        )
                    )

                    HStack(spacing: 10) {
                        Button {
                            viewModel.applyRecommendedScanSchedule()
                        } label: {
                            Label("Enable recommended schedule", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        if viewModel.volumeScanSchedule.fastScanEnabled || viewModel.volumeScanSchedule.deepScanEnabled {
                            Button("Run now") {
                                viewModel.runDueScheduledScansNow()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var recommendationCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended timing")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fast: \(ScanScheduleAdvisor.fastScanSummary(for: ScanScheduleAdvisor.recommendedSchedule()))")
                        .font(.caption.weight(.semibold))
                    Text(ScanScheduleAdvisor.fastScanRationale())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep: \(ScanScheduleAdvisor.deepScanSummary(for: ScanScheduleAdvisor.recommendedSchedule()))")
                        .font(.caption.weight(.semibold))
                    Text(ScanScheduleAdvisor.deepScanRationale())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func scheduleRow(
        title: String,
        icon: String,
        summary: String,
        rationale: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(icon == "scope" ? .orange : .yellow)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan history")
                .font(.headline)

            if viewModel.selectedVolume == nil {
                ContentUnavailableView {
                    Label("Select a drive", systemImage: "internaldrive")
                } description: {
                    Text("Choose a drive to see past fast and deep scans with major usage snapshots.")
                }
            } else if viewModel.scanHistoryRecords.isEmpty {
                ContentUnavailableView {
                    Label("No scan history yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Complete a fast or deep scan on this drive and DiskWise will record category usage here.")
                }
            } else {
                ForEach(viewModel.scanHistoryRecords) { record in
                    scanHistoryCard(record)
                }
            }
        }
    }

    private func scanHistoryCard(_ record: ScanHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                modeBadge(record.scanMode)
                Text(relativeDate(record.scannedAt))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(durationLabel(record.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                metricLabel("Files", "\(record.fileCount.formatted())")
                metricLabel("Indexed", DiskWiseFormatters.bytes.string(fromByteCount: record.indexedBytes))
                metricLabel("Free then", DiskWiseFormatters.bytes.string(fromByteCount: record.freeBytes))
            }

            if let snapshot = record.decodedSnapshot(), !snapshot.majorCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Major usage")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(snapshot.majorCategories, id: \.category.rawValue) { summary in
                        categoryUsageRow(summary, totalBytes: record.indexedBytes)
                    }

                    if !snapshot.topConsumers.isEmpty {
                        Text("Top folders: \(snapshot.topConsumers.prefix(3).map(\.name).joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func modeBadge(_ rawMode: String) -> some View {
        let isDeep = rawMode == ScanMode.deep.rawValue
        return Text(isDeep ? "Deep" : "Fast")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isDeep ? Color.orange : Color.accentColor).opacity(0.18), in: Capsule())
            .foregroundStyle(isDeep ? .orange : Color.accentColor)
    }

    private func metricLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
    }

    private func categoryUsageRow(_ summary: CategorySummary, totalBytes: Int64) -> some View {
        let fraction = totalBytes > 0 ? Double(summary.totalSize) / Double(totalBytes) : 0
        return HStack(spacing: 10) {
            Image(systemName: summary.category.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(summary.category.granularName)
                .font(.caption)
                .frame(width: 92, alignment: .leading)
            ProgressView(value: fraction)
                .tint(Color.accentColor)
            Text(DiskWiseFormatters.bytes.string(fromByteCount: summary.totalSize))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func durationLabel(_ seconds: Double) -> String {
        guard seconds >= 1 else { return "< 1 min" }
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }
        if seconds < 3_600 {
            return "\(Int((seconds / 60).rounded())) min"
        }
        return String(format: "%.1f hr", seconds / 3_600)
    }
}
