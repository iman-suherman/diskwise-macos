import SwiftUI
import Charts
import AppKit
import DatabaseKit
import AIKit
import DiskScannerKit

struct StorageRingChart: View {
    let usedSize: Int64
    let freeSize: Int64
    let totalSize: Int64

    private var usedFraction: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize)
    }

    var body: some View {
        ZStack {
            Chart {
                SectorMark(
                    angle: .value("Used", usedSize),
                    innerRadius: .ratio(0.68),
                    angularInset: 2
                )
                .foregroundStyle(Color.accentColor)

                SectorMark(
                    angle: .value("Free", freeSize),
                    innerRadius: .ratio(0.68),
                    angularInset: 2
                )
                .foregroundStyle(Color.accentColor.opacity(0.15))
            }
            .frame(width: 180, height: 180)

            VStack(spacing: 2) {
                Text("\(Int(usedFraction * 100))%")
                    .font(.title.bold())
                Text("Used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StorageCategoryChart: View {
    let summaries: [(name: String, totalSize: Int64, fileCount: Int)]
    let totalSize: Int64

    var body: some View {
        Chart(summaries, id: \.name) { summary in
            BarMark(
                x: .value("Size", summary.totalSize),
                y: .value("Category", summary.name)
            )
            .foregroundStyle(CategoryPalette.color(for: summary.name).gradient)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, position: .bottom)
        }
        .frame(height: max(180, CGFloat(summaries.count * 34)))
    }
}

struct ScanProgressPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let volume = viewModel.selectedVolume {
                        Text("Scanning \(volume.name)")
                            .font(.title2.bold())
                    }
                    Label(viewModel.scanPhase.label, systemImage: phaseIcon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 8)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: viewModel.scanProgressFraction)
                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 72, height: 72)
                        .animation(.easeInOut(duration: 0.35), value: viewModel.scanProgressFraction)
                    Text(viewModel.scanProgressPercentLabel)
                        .font(.title3.bold().monospacedDigit())
                }

                Button("Cancel") {
                    viewModel.cancelScan()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.scanProgressPercentLabel)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if let remaining = viewModel.scanEstimatedRemaining {
                        Text("~\(DiskWiseFormatters.formatDuration(remaining)) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                        Capsule()
                            .fill(Color.accentColor.gradient)
                            .frame(width: max(8, geometry.size.width * viewModel.scanProgressFraction))
                            .animation(.easeInOut(duration: 0.35), value: viewModel.scanProgressFraction)
                    }
                }
                .frame(height: 12)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let progress = viewModel.scanProgress {
                    ScanStatTile(
                        title: "Files",
                        value: progress.scannedCount.formatted(),
                        icon: "doc.text"
                    )
                    ScanStatTile(
                        title: "Processed",
                        value: DiskWiseFormatters.bytes.string(fromByteCount: progress.bytesIndexed),
                        icon: "externaldrive"
                    )
                    ScanStatTile(
                        title: "Progress",
                        value: viewModel.scanProgressPercentLabel,
                        icon: "gauge.with.dots.needle.67percent"
                    )
                }
            }

            if let progress = viewModel.scanProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current file")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(progress.currentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }

    private var phaseIcon: String {
        switch viewModel.scanPhase {
        case .scanning: return "doc.text.magnifyingglass"
        case .findingDuplicates: return "doc.on.doc"
        case .analyzing: return "sparkles"
        case .idle: return "checkmark.circle"
        }
    }
}

private struct ScanStatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    let detail: String
    var accent: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(accent)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            AppBrandIcon(size: 112)

            VStack(spacing: 12) {
                Text("Welcome to DiskWise")
                    .font(.largeTitle.bold())

                Text("Understand what's using your storage, find duplicates, and reclaim disk space safely.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "chart.pie", text: "Visual storage breakdown by category")
                FeatureRow(icon: "doc.on.doc", text: "Find duplicate files automatically")
                FeatureRow(icon: "sparkles", text: "AI-powered cleanup recommendations")
                FeatureRow(icon: "trash", text: "Safe cleanup — always moves to Trash first")
            }
            .padding(.vertical, 8)

            HStack(spacing: 16) {
                Button {
                    viewModel.scanInternalDrive()
                } label: {
                    Label("Scan Macintosh HD", systemImage: "internaldrive.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isScanning || viewModel.mountedVolumes.isEmpty)

                if let external = viewModel.externalVolumes.first {
                    Button {
                        viewModel.selectVolume(external, autoScan: true)
                    } label: {
                        Label("Choose External Drive", systemImage: "externaldrive.fill")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isScanning)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }
}

private struct AppBrandIcon: View {
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let image = Self.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: size * 0.58))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private static func loadImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIconSource", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "AppIconSource")
    }
}

struct DashboardView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.isScanning {
                    ScanProgressPanel()
                }

                if let volume = viewModel.selectedVolume,
                   viewModel.isScanning || viewModel.overview != nil {
                    if let overview = viewModel.overview {
                        storageHeader(volume: volume, overview: overview)
                    } else {
                        scanningHeader(volume: volume)
                    }

                    HStack(alignment: .top, spacing: 24) {
                        storageRingSection(volume: volume)
                        if let overview = viewModel.overview {
                            categorySection(overview: overview)
                        } else {
                            categorySectionPlaceholder
                        }
                    }

                    if !viewModel.topConsumers.isEmpty {
                        topConsumersSection
                    }

                    if let report = viewModel.analysisReport {
                        storageIntelligenceSection(report: report)
                        recommendationsSection(report: report)
                    }
                } else if !viewModel.isScanning {
                    WelcomeView()
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private func storageHeader(volume: MountedVolume, overview: StorageOverview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(volume.name)
                .font(.largeTitle.bold())
            Text("Storage Overview")
                .font(.title3)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 16) {
            InsightCard(
                title: "Total",
                value: DiskWiseFormatters.bytes.string(fromByteCount: volume.totalSize),
                detail: "\(overview.fileCount.formatted()) files indexed"
            )
            InsightCard(
                title: "Used",
                value: DiskWiseFormatters.bytes.string(fromByteCount: volume.usedSize),
                detail: "\(Int(volume.usageFraction * 100))% of capacity"
            )
            InsightCard(
                title: "Free",
                value: DiskWiseFormatters.bytes.string(fromByteCount: volume.freeSize),
                detail: "Available space",
                accent: .green
            )
            if let report = viewModel.analysisReport, report.potentialReclaimableSpace > 0 {
                InsightCard(
                    title: "Potential Savings",
                    value: DiskWiseFormatters.bytes.string(fromByteCount: report.potentialReclaimableSpace),
                    detail: "From recommendations",
                    accent: .orange
                )
            }
        }
    }

    @ViewBuilder
    private func storageRingSection(volume: MountedVolume) -> some View {
        GroupBox("Capacity") {
            VStack(spacing: 16) {
                StorageRingChart(
                    usedSize: volume.usedSize,
                    freeSize: volume.freeSize,
                    totalSize: volume.totalSize
                )

                HStack(spacing: 20) {
                    legendItem(color: .accentColor, label: "Used", value: volume.usedSize)
                    legendItem(color: .accentColor.opacity(0.2), label: "Free", value: volume.freeSize)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private func scanningHeader(volume: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(volume.name)
                .font(.largeTitle.bold())
            Text("Building storage breakdown…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var categorySectionPlaceholder: some View {
        GroupBox("Storage by Type") {
            VStack(spacing: 12) {
                ProgressView()
                Text("Category breakdown appears as files are indexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func categorySection(overview: StorageOverview) -> some View {
        let grouped = viewModel.groupedCategorySummaries(from: overview.categorySummaries)

        GroupBox("Storage by Type") {
            if grouped.isEmpty {
                Text("No category data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if let selected = viewModel.selectedStorageCategory {
                StorageCategoryDetailPanel(
                    groupName: selected,
                    subSummaries: viewModel.subSummaries(forChartGroup: selected),
                    files: viewModel.categoryDetailFiles,
                    totalSize: grouped.first(where: { $0.name == selected })?.totalSize ?? overview.totalSize,
                    onBack: { viewModel.clearStorageCategorySelection() }
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    StorageCategoryBarChart(
                        items: grouped,
                        totalSize: overview.totalSize,
                        selectedName: viewModel.selectedStorageCategory,
                        onSelect: { viewModel.selectStorageCategory($0) }
                    )

                    Divider()

                    StorageCategoryChart(summaries: grouped, totalSize: overview.totalSize)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topConsumersSection: some View {
        GroupBox("Biggest Space Consumers") {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.topConsumers.enumerated()), id: \.element.id) { index, consumer in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(consumer.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(DiskWiseFormatters.bytes.string(fromByteCount: consumer.totalSize))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    if index < viewModel.topConsumers.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func storageIntelligenceSection(report: AnalysisReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Storage Intelligence", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text("Potential savings: \(DiskWiseFormatters.bytes.string(fromByteCount: report.potentialReclaimableSpace))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.insights.filter { $0.estimatedSavings > 0 }, id: \.id) { insight in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(DiskWiseFormatters.bytes.string(fromByteCount: insight.estimatedSavings)) \(insight.title.lowercased())")
                                    .font(.subheadline.weight(.medium))
                                Text(insight.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func recommendationsSection(report: AnalysisReport) -> some View {
        GroupBox("Recommended Actions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(report.recommendations.enumerated()), id: \.offset) { _, recommendation in
                    RecommendationActionCard(recommendation: recommendation) {
                        viewModel.handleRecommendation(recommendation)
                    }
                }
            }
        }
    }

    private func legendItem(color: Color, label: String, value: Int64) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
            Text(DiskWiseFormatters.bytes.string(fromByteCount: value))
                .font(.caption.weight(.medium))
        }
    }
}

struct RecommendationActionCard: View {
    let recommendation: RecommendationRecord
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recommendation.title)
                .font(.headline)
            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Text("Save \(DiskWiseFormatters.bytes.string(fromByteCount: recommendation.estimatedSavings))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Review") {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
