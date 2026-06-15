import SwiftUI
import Charts
import AppKit
import DatabaseKit
import AIKit
import DiskScannerKit

struct ScanTheme {
    let mode: ScanMode

    var isDeepScan: Bool { mode == .deep }
    var accent: Color { isDeepScan ? .orange : Color.accentColor }

    static func current(_ mode: ScanMode) -> ScanTheme {
        ScanTheme(mode: mode)
    }
}

struct ScanProgressPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var theme: ScanTheme {
        ScanTheme.current(viewModel.activeScanMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if theme.isDeepScan {
                DeepScanIndicator(theme: theme)
            }

            ScanPanelHeader(
                title: viewModel.selectedVolume.map { "Identifying usage on \($0.name)" } ?? "Identifying disk usage",
                subtitle: viewModel.scanPhase.label,
                icon: "doc.text.magnifyingglass",
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                theme: theme,
                onCancel: { viewModel.cancelScan() }
            )

            ScanStepList(
                activeStep: viewModel.scanPhase.stepNumber,
                duplicateDetail: nil,
                theme: theme
            )

            ScanProgressBar(
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                estimatedRemaining: viewModel.scanEstimatedRemaining,
                theme: theme
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
                        icon: "doc.text",
                        theme: theme
                    )
                    ScanStatTile(
                        title: "Processed",
                        value: DiskWiseFormatters.bytes.string(fromByteCount: progress.bytesIndexed),
                        icon: "externaldrive",
                        theme: theme
                    )
                    ScanStatTile(
                        title: "Folders",
                        value: foldersLabel(for: progress),
                        icon: "folder",
                        theme: theme
                    )
                }
            }

            ScanVerboseLogPanel(scanMode: viewModel.isScanning ? viewModel.activeScanMode : .fast)
        }
        .scanPanelStyle(theme: theme)
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
    let scanMode: ScanMode
    @ObservedObject private var scanLogMonitor = ScanLogMonitor.shared
    @State private var copiedCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scanner log", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))

            if let tailCommand = scanLogMonitor.tailCommand {
                Text("Verbose output is written to a log file. Open Terminal to follow it live with tail -f, or copy the command below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 8) {
                    Text(tailCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(copiedCommand ? "Copied" : "Copy") {
                        scanLogMonitor.copyTailCommand()
                        copiedCommand = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Open in Terminal") {
                    scanLogMonitor.openInTerminal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(scanMode == .deep ? .orange : nil)
            } else if scanLogMonitor.isActive {
                Text("Preparing scanner log…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("When a Python scan starts, a tail command appears here for live log monitoring in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scanMode == .deep {
                deepScanExplanation
            }
        }
    }

    private var deepScanExplanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("About deep scan", systemImage: "scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(scanMode.scanningLogExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        }
    }
}

struct BackgroundScanBanner: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var theme: ScanTheme {
        ScanTheme.current(viewModel.activeScanMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if theme.isDeepScan {
                DeepScanIndicator(theme: theme)
            }

            ScanPanelHeader(
                title: "Analyzing storage",
                subtitle: viewModel.scanPhase.label,
                icon: "sparkles",
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                theme: theme,
                onCancel: { viewModel.cancelScan() }
            )

            ScanStepList(
                activeStep: viewModel.scanPhase.stepNumber,
                duplicateDetail: nil,
                theme: theme
            )

            ScanProgressBar(
                progressFraction: viewModel.scanProgressFraction,
                progressLabel: viewModel.scanProgressPercentLabel,
                estimatedRemaining: viewModel.scanEstimatedRemaining,
                theme: theme
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

            if viewModel.showsStorageGraphAnalysis {
                Label("You can review storage breakdown below while this runs.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scanPanelStyle(theme: theme)
    }
}

private struct DeepScanIndicator: View {
    let theme: ScanTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.caption.weight(.semibold))
                .symbolEffect(.pulse, options: .repeating)
            Text("Deep Scan in progress")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Thorough indexing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.accent.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct ScanStepList: View {
    let activeStep: Int?
    let duplicateDetail: String?
    var theme: ScanTheme = ScanTheme(mode: .fast)

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
        if number == activeStep { return theme.accent }
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
    var theme: ScanTheme = ScanTheme(mode: .fast)
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
                    .stroke(theme.accent.opacity(0.15), lineWidth: 8)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(theme.accent.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.35), value: progressFraction)
                Text(progressLabel)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(theme.isDeepScan ? theme.accent : .primary)
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
    var theme: ScanTheme = ScanTheme(mode: .fast)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progressLabel)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.accent)
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
                        .fill(theme.accent.opacity(0.12))
                    Capsule()
                        .fill(theme.accent.gradient)
                        .frame(width: max(8, geometry.size.width * progressFraction))
                        .animation(.easeInOut(duration: 0.35), value: progressFraction)
                }
            }
            .frame(height: 12)
        }
    }
}

private extension View {
    func scanPanelStyle(theme: ScanTheme = ScanTheme(mode: .fast)) -> some View {
        padding(22)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if theme.isDeepScan {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1.5)
                        }
                    }
                    .shadow(
                        color: theme.isDeepScan ? theme.accent.opacity(0.12) : .black.opacity(0.08),
                        radius: 12,
                        y: 4
                    )
            }
    }
}

private struct ScanStatTile: View {
    let title: String
    let value: String
    let icon: String
    var theme: ScanTheme = ScanTheme(mode: .fast)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(theme.isDeepScan ? theme.accent.opacity(0.85) : .secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            (theme.isDeepScan ? theme.accent.opacity(0.08) : Color.primary.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 10)
        )
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
                        viewModel.selectVolume(external)
                        viewModel.presentScanModePrompt(for: external)
                    } label: {
                        Label("Scan External Drive", systemImage: "externaldrive.fill")
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

struct AppBrandIcon: View {
    var size: CGFloat = 96
    var showsShadow: Bool = true

    var body: some View {
        Group {
            if NSImage(named: "BrandIcon") != nil {
                Image("BrandIcon")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let image = Self.loadImage() {
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
        .shadow(
            color: showsShadow ? .black.opacity(0.18) : .clear,
            radius: showsShadow ? 10 : 0,
            y: showsShadow ? 4 : 0
        )
    }

    static func loadImage() -> NSImage? {
        if let image = NSImage(named: "BrandIcon") {
            return normalized(image)
        }
        if let url = Bundle.main.url(forResource: "AppIconSource", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return normalized(image)
        }
        if let image = NSImage(named: "AppIconSource") {
            return normalized(image)
        }
        return nil
    }

    private static func normalized(_ image: NSImage) -> NSImage {
        image.isTemplate = false
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).max(by: { $0.pixelsWide < $1.pixelsWide }) else {
            return image
        }
        let pixelSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let normalized = NSImage(size: pixelSize)
        normalized.addRepresentation(rep)
        return normalized
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
                   viewModel.showsStorageGraphAnalysis,
                   let overview = viewModel.overview {
                    storageHeader(volume: volume, overview: overview)

                    StorageResultsChartsSection(volume: volume, overview: overview)

                    if viewModel.totalDuplicateSavings > 0 {
                        duplicatesCallToAction
                    }

                    if !viewModel.topConsumers.isEmpty {
                        topConsumersSection
                    }

                    if let report = viewModel.analysisReport {
                        StorageCleanupInsightsSection(report: report)
                    }
                } else if let volume = viewModel.selectedVolume,
                          (viewModel.isScanning || viewModel.isVolumeBusy(volume)) {
                    if viewModel.isScanning {
                        ScanProgressPanel()
                    } else {
                        BackgroundScanBanner()
                    }
                } else if viewModel.selectedVolume != nil {
                    unscannedVolumePlaceholder
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
        .sheet(item: $viewModel.categoryCleanupPreview) { preview in
            CleanupPreviewSheet(
                preview: preview,
                subject: "file\(preview.items.count == 1 ? "" : "s")"
            ) { _ in
                viewModel.dismissCategoryCleanupPreview()
                viewModel.reload()
            }
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
                    viewModel.openDuplicatesPane(review: true)
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
                accent: MenuBarDiskThresholds.statusColor(for: volume)
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
                    detail: viewModel.unaccountedStorageDetail(volume: volume, overview: overview),
                    accent: .red
                )
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

    private var unscannedVolumePlaceholder: some View {
        ContentUnavailableView {
            Label("No scan results yet", systemImage: "chart.pie")
        } description: {
            if let volume = viewModel.selectedVolume {
                Text("Scan \(volume.name) to see storage breakdown charts and top space consumers.")
            } else {
                Text("Select a drive and scan it to see storage breakdown charts.")
            }
        } actions: {
            if let volume = viewModel.selectedVolume {
                Button("Scan \(volume.name)") {
                    viewModel.requestScan(for: volume)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isVolumeBusy(volume))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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
}
