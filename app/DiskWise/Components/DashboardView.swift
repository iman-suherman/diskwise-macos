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
                title: viewModel.selectedVolume.map { "Identifying usage on \($0.name)" } ?? "Identifying disk usage",
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

            if let detail = viewModel.scanProgressDetail {
                Label(detail, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !viewModel.hasFullDiskAccess {
                Label(
                    "Without Full Disk Access, protected folders are sized approximately and may show as not mapped until you rescan.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
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
                        title: "Folders",
                        value: foldersLabel(for: progress),
                        icon: "folder"
                    )
                }
            }

            if let progress = viewModel.scanProgress,
               let identified = progress.identifiedDirectories,
               !identified.isEmpty {
                ScanConcurrencyPanel(progress: progress, identifiedDirectories: identified)
            }

            if let progress = viewModel.scanProgress {
                currentPathPanel(
                    title: progress.operation == .sizingDirectory ? "Current folder" : "Current path",
                    path: progress.currentPath
                )
            }

            ScanVerboseLogPanel()
        }
        .scanPanelStyle()
    }

    private func foldersLabel(for progress: ScanProgress) -> String {
        let completed = progress.directoriesProcessed ?? 0
        let total = progress.directoriesTotal ?? 0
        if total > 0 {
            return "\(completed)/\(total)"
        }
        return "—"
    }
}

struct ScanVerboseLogPanel: View {
    @ObservedObject private var scanLogMonitor = ScanLogMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scanner log", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if scanLogMonitor.logFileURL != nil {
                    Button("Open in Terminal") {
                        scanLogMonitor.openInTerminal()
                    }
                    .buttonStyle(.link)
                    .help("Open Terminal and tail the verbose Python scanner log")
                }
            }

            if scanLogMonitor.logLines.isEmpty {
                Text("Verbose scanner output will appear here while the Python scan runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(scanLogMonitor.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let logFileURL = scanLogMonitor.logFileURL {
                Text(logFileURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct BackgroundScanBanner: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScanPanelHeader(
                title: "Analyzing storage",
                subtitle: viewModel.scanPhase.label,
                icon: "sparkles",
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

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sorting findings into action buckets…")
                    Text("Safe to clean · Review first · Personal — keep")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Analyzing largest \(viewModel.appSettings.analysisFileLimit.formatted()) files")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if viewModel.hasScanData {
                Label("You can review storage breakdown below while this runs.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scanPanelStyle()
    }
}

private struct ScanStepList: View {
    let activeStep: Int?
    let duplicateDetail: String?

    private let steps: [(number: Int, title: String, detail: String)] = [
        (1, "Identify usage", "Map APFS volumes and drill into the biggest directories"),
        (2, "Analyze storage", "Sort findings into safe, review-first, and personal buckets"),
        (3, "Take action", "Use Maintenance tools or review recommendations below"),
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
        if step.number == 2, activeStep == 2 {
            return "Building action plan from indexed files…"
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

private struct ScanConcurrencyPanel: View {
    let progress: ScanProgress
    let identifiedDirectories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Directory queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let completed = progress.directoriesProcessed,
                   let total = progress.directoriesTotal {
                    Text("\(completed)/\(total) done")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if let active = progress.activeDirectories, !active.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current folder")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(active, id: \.self) { directory in
                        Label(directory, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(identifiedDirectories, id: \.self) { directory in
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: directory))
                                .font(.caption2)
                                .foregroundStyle(iconColor(for: directory))
                                .frame(width: 12)
                            Text(directory)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func iconName(for directory: String) -> String {
        if progress.activeDirectories?.contains(directory) == true {
            return "arrow.triangle.2.circlepath"
        }
        if progress.completedDirectories?.contains(directory) == true {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private func iconColor(for directory: String) -> Color {
        if progress.activeDirectories?.contains(directory) == true {
            return .accentColor
        }
        if progress.completedDirectories?.contains(directory) == true {
            return .green
        }
        return .secondary.opacity(0.5)
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
            .lineLimit(3)
            .truncationMode(.middle)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .padding(10)
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

                Text("Identify what's using your storage, get a prioritized action plan, and reclaim space safely.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "chart.pie", text: "Three-phase storage consultant workflow")
                FeatureRow(icon: "checkmark.seal", text: "Action buckets: safe, review-first, personal")
                FeatureRow(icon: "doc.on.doc", text: "Dedicated Duplicates tab when you need it")
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
                        unaccountedSpaceBanner(volume: volume, overview: overview)
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

                    if viewModel.totalDuplicateSavings > 0 || viewModel.isFindingDuplicates {
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

            let unaccounted = max(0, volume.usedSize - overview.totalSize)
            if unaccounted > 1_073_741_824 {
                InsightCard(
                    title: "Not Indexed",
                    value: DiskWiseFormatters.bytes.string(fromByteCount: unaccounted),
                    detail: unaccountedDetail(for: volume, overview: overview),
                    accent: .red
                )
            }
        }
    }

    private func unaccountedDetail(for volume: MountedVolume, overview: StorageOverview) -> String {
        let coverage = volume.usedSize > 0
            ? Int((Double(overview.totalSize) / Double(volume.usedSize) * 100).rounded())
            : 0
        if !viewModel.hasFullDiskAccess {
            return "Only \(coverage)% mapped — grant Full Disk Access, then rescan"
        }
        if coverage < 50 {
            return "Only \(coverage)% mapped — rescan after granting Full Disk Access"
        }
        if viewModel.appSettings.scanMode == .fast {
            return "Only \(coverage)% mapped — try Deep scan or rescan"
        }
        return "Only \(coverage)% mapped — may include APFS snapshots or purgeable space"
    }

    @ViewBuilder
    private func unaccountedSpaceBanner(volume: MountedVolume, overview: StorageOverview) -> some View {
        let unaccounted = max(0, volume.usedSize - overview.totalSize)
        let fraction = volume.usedSize > 0 ? Double(unaccounted) / Double(volume.usedSize) : 0
        if unaccounted > 1_073_741_824, fraction > 0.1 {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("About \(DiskWiseFormatters.bytes.string(fromByteCount: unaccounted)) is not mapped yet", systemImage: "questionmark.folder")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(unaccountedDetail(for: volume, overview: overview) + ". Rescan after granting Full Disk Access if needed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if !viewModel.hasFullDiskAccess {
                            Button("Grant Full Disk Access") {
                                viewModel.presentFullDiskAccessOverlay()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let volume = viewModel.selectedVolume {
                            Button("Rescan \(volume.name)") {
                                viewModel.scan(volume: volume)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

                if !viewModel.aiAnalysisSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(viewModel.aiProviderStatus.displayName, systemImage: "brain.head.profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(viewModel.aiAnalysisSummary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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

                if viewModel.aiProviderStatus.isGenerativeAvailable {
                    Button {
                        viewModel.generateLLMReport()
                    } label: {
                        Label("Regenerate AI Summary", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAnalyzing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func recommendationsSection(report: AnalysisReport) -> some View {
        ForEach(ActionBucket.allCases) { bucket in
            let items = report.recommendationsByBucket[bucket, default: []]
            if !items.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(bucket.title, systemImage: bucket.icon)
                            .font(.headline)
                            .foregroundStyle(bucketColor(bucket))

                        Text(bucket.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, recommendation in
                                RecommendationActionCard(recommendation: recommendation, bucket: bucket) {
                                    viewModel.handleRecommendation(recommendation)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func bucketColor(_ bucket: ActionBucket) -> Color {
        switch bucket {
        case .safeRegenerable: return .green
        case .reviewFirst: return .orange
        case .personalKeep: return .blue
        }
    }
}

struct RecommendationActionCard: View {
    let recommendation: RecommendationRecord
    let bucket: ActionBucket
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(recommendation.title)
                    .font(.headline)
                Spacer()
                Text(bucket.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(bucketBadgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(bucketBadgeColor)
            }
            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack {
                if recommendation.estimatedSavings > 0 {
                    Text("Save \(DiskWiseFormatters.bytes.string(fromByteCount: recommendation.estimatedSavings))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(bucket == .personalKeep ? "Review" : "Take Action") {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bucketBadgeColor: Color {
        switch bucket {
        case .safeRegenerable: return .green
        case .reviewFirst: return .orange
        case .personalKeep: return .blue
        }
    }
}
