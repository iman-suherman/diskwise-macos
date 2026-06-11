import SwiftUI
import Charts
import AppKit
import DatabaseKit
import AIKit
import DiskScannerKit

struct StorageTypePieChart: View {
    let items: [(name: String, totalSize: Int64, fileCount: Int)]
    let totalSize: Int64
    let hoveredName: String?

    var body: some View {
        ZStack {
            Chart(items, id: \.name) { item in
                SectorMark(
                    angle: .value("Size", item.totalSize),
                    innerRadius: .ratio(0.58),
                    angularInset: 2
                )
                .foregroundStyle(CategoryPalette.color(for: item.name).gradient)
                .opacity(segmentOpacity(for: item.name))
            }
            .frame(width: 300, height: 300)

            VStack(spacing: 4) {
                if let hoveredName,
                   let item = items.first(where: { $0.name == hoveredName }) {
                    Image(systemName: CategoryPalette.icon(for: hoveredName))
                        .font(.title3)
                        .foregroundStyle(CategoryPalette.color(for: hoveredName))
                    Text(hoveredName)
                        .font(.headline)
                    Text("\(Int(fraction(for: item.totalSize) * 100))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: item.totalSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Indexed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: totalSize))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("\(items.count) types")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 140)
        }
        .animation(.easeInOut(duration: 0.2), value: hoveredName)
    }

    private func fraction(for size: Int64) -> Double {
        guard totalSize > 0 else { return 0 }
        return Double(size) / Double(totalSize)
    }

    private func segmentOpacity(for name: String) -> Double {
        guard let hoveredName else { return 1 }
        return hoveredName == name ? 1 : 0.22
    }
}

struct ScanProgressPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScanPanelHeader(
                title: viewModel.selectedVolume.map { "Scanning \($0.name)" } ?? "Scanning",
                subtitle: viewModel.scanPhase.label,
                icon: "doc.text.magnifyingglass",
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                onCancel: { viewModel.cancelScan() }
            )

            ScanStepList(
                activeStep: viewModel.scanPhase.stepNumber,
                duplicateDetail: nil
            )

            ScanProgressBar(
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                estimatedRemaining: viewModel.scanEstimatedRemaining
            )

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
                currentPathPanel(title: "Current file", path: progress.currentPath)
            }
        }
        .scanPanelStyle()
    }
}

struct BackgroundScanBanner: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScanPanelHeader(
                title: bannerTitle,
                subtitle: bannerSubtitle,
                icon: bannerIcon,
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                onCancel: { viewModel.cancelDuplicateDetection() }
            )

            ScanStepList(
                activeStep: viewModel.scanPhase.stepNumber,
                duplicateDetail: viewModel.duplicateScanProgress?.level.detail
            )

            ScanProgressBar(
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                estimatedRemaining: viewModel.scanEstimatedRemaining
            )

            if let progress = viewModel.duplicateScanProgress {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ScanStatTile(
                        title: "Step",
                        value: "\(progress.levelIndex + 1) of \(progress.levelCount)",
                        icon: "list.number"
                    )
                    ScanStatTile(
                        title: progress.level == .videoFingerprint ? "Videos" : "Files",
                        value: "\(progress.processedCount.formatted()) / \(progress.totalCount.formatted())",
                        icon: progress.level == .videoFingerprint ? "film" : "doc.text"
                    )
                    ScanStatTile(
                        title: "Groups",
                        value: progress.groupsFoundSoFar.formatted(),
                        icon: "doc.on.doc"
                    )
                }

                currentPathPanel(title: "Checking", path: progress.currentPath)
            } else if viewModel.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Building recommendations from your indexed files…")
                        Text("Analyzing largest \(viewModel.appSettings.analysisFileLimit.formatted()) files")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if viewModel.hasScanData {
                Label("You can review storage breakdown below while this runs.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scanPanelStyle()
    }

    private var bannerTitle: String {
        if viewModel.isAnalyzing {
            return "Analyzing storage"
        }
        if let volume = viewModel.selectedVolume {
            return "Checking duplicates on \(volume.name)"
        }
        return "Checking duplicates"
    }

    private var bannerSubtitle: String {
        viewModel.duplicateProgressDetail ?? viewModel.scanPhase.label
    }

    private var bannerIcon: String {
        viewModel.isAnalyzing ? "sparkles" : "doc.on.doc"
    }
}

private struct ScanStepList: View {
    let activeStep: Int?
    let duplicateDetail: String?

    private let steps: [(number: Int, title: String, detail: String)] = [
        (1, "Scan files", "Walk the drive and index every file"),
        (2, "Find duplicates", "Match names, sizes, hashes, and video fingerprints"),
        (3, "Analyze storage", "Build cleanup recommendations"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps, id: \.number) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: stepIcon(for: step.number))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stepColor(for: step.number))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(step.number) · \(step.title)")
                            .font(.subheadline.weight(step.number == activeStep ? .semibold : .regular))
                        Text(stepDetail(for: step))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stepIcon(for number: Int) -> String {
        guard let activeStep else { return "circle" }
        if number < activeStep { return "checkmark.circle.fill" }
        if number == activeStep { return "arrow.triangle.2.circlepath.circle.fill" }
        return "circle"
    }

    private func stepColor(for number: Int) -> Color {
        guard let activeStep else { return .secondary }
        if number < activeStep { return .green }
        if number == activeStep { return .accentColor }
        return .secondary.opacity(0.5)
    }

    private func stepDetail(for step: (number: Int, title: String, detail: String)) -> String {
        if step.number == 2, let duplicateDetail, activeStep == 2 {
            return duplicateDetail
        }
        return step.detail
    }
}

private struct ScanPanelHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let progressFraction: Double
    let progressLabel: String
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Label(subtitle, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 8)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.35), value: progressFraction)
                Text(progressLabel)
                    .font(.title3.bold().monospacedDigit())
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
    }
}

private struct ScanProgressBar: View {
    let progressFraction: Double
    let progressLabel: String
    let estimatedRemaining: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progressLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let remaining = estimatedRemaining {
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
                        .frame(width: max(8, geometry.size.width * progressFraction))
                        .animation(.easeInOut(duration: 0.35), value: progressFraction)
                }
            }
            .frame(height: 12)
        }
    }
}

private func currentPathPanel(title: String, path: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text(path)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(2)
            .truncationMode(.middle)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func scanPanelStyle() -> some View {
        padding(22)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
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
                } else if viewModel.isBackgroundWorkActive {
                    BackgroundScanBanner()
                }

                if let volume = viewModel.selectedVolume,
                   viewModel.isScanning || viewModel.isBackgroundWorkActive || viewModel.overview != nil {
                    if let overview = viewModel.overview {
                        storageHeader(volume: volume, overview: overview)
                    } else {
                        scanningHeader(volume: volume)
                    }

                    HStack(alignment: .top, spacing: 28) {
                        if let overview = viewModel.overview {
                            storageTypePieSection(overview: overview)
                            categorySection(overview: overview)
                        } else {
                            storageTypePiePlaceholder
                            categorySectionPlaceholder
                        }
                    }

                    if viewModel.totalDuplicateSavings > 0 {
                        duplicatesCallToAction
                    }

                    if !viewModel.topConsumers.isEmpty {
                        topConsumersSection
                    }

                    if let report = viewModel.analysisReport {
                        storageIntelligenceSection(report: report)
                        recommendationsSection(report: report)
                    }
                } else if !viewModel.isScanning && !viewModel.isBackgroundWorkActive {
                    WelcomeView()
                }
            }
            .padding(28)
        }
        .sheet(item: $viewModel.recommendationReview) { review in
            RecommendationReviewSheet(state: review)
                .environmentObject(viewModel)
        }
    }

    private var duplicatesCallToAction: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.duplicateGroups.count) duplicate groups found")
                        .font(.headline)
                    Text("\(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.totalDuplicateSavings)) can be reclaimed by moving extra copies to Trash.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.openDuplicatesPane()
                } label: {
                    Label("Review & Delete Duplicates", systemImage: "trash.fill")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private func storageTypePieSection(overview: StorageOverview) -> some View {
        let grouped = viewModel.groupedCategorySummaries(from: overview.categorySummaries)

        GroupBox("Storage by Type") {
            VStack(spacing: 18) {
                StorageTypePieChart(
                    items: grouped,
                    totalSize: overview.totalSize,
                    hoveredName: viewModel.hoveredStorageCategory
                )

                if !grouped.isEmpty {
                    Divider()
                    pieLegend(items: grouped, totalSize: overview.totalSize)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 440)
    }

    private var storageTypePiePlaceholder: some View {
        GroupBox("Storage by Type") {
            VStack(spacing: 12) {
                ProgressView()
                Text("Pie chart appears as files are indexed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 440)
    }

    private func pieLegend(
        items: [(name: String, totalSize: Int64, fileCount: Int)],
        totalSize: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.prefix(6), id: \.name) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(CategoryPalette.color(for: item.name))
                        .frame(width: 8, height: 8)
                    Text(item.name)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(totalSize > 0 ? Double(item.totalSize) / Double(totalSize) * 100 : 0))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .opacity(
                    viewModel.hoveredStorageCategory == nil || viewModel.hoveredStorageCategory == item.name
                        ? 1
                        : 0.35
                )
                .onHover { hovering in
                    viewModel.hoveredStorageCategory = hovering ? item.name : nil
                }
            }
        }
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
        GroupBox("Storage Breakdown") {
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

        GroupBox("Storage Breakdown") {
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
                StorageCategoryBarChart(
                    items: grouped,
                    totalSize: overview.totalSize,
                    selectedName: viewModel.selectedStorageCategory,
                    hoveredName: viewModel.hoveredStorageCategory,
                    onSelect: { viewModel.selectStorageCategory($0) },
                    onHover: { viewModel.hoveredStorageCategory = $0 }
                )
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
