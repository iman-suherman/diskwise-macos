import SwiftUI
import Charts
import DatabaseKit
import AIKit
import DiskScannerKit

enum VolumeDiskTab: String, CaseIterable, Identifiable {
    case overview
    case breakdown
    case history
    case schedule
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .breakdown: return "Breakdown"
        case .history: return "History"
        case .schedule: return "Schedule"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "internaldrive"
        case .breakdown: return "chart.pie"
        case .history: return "clock.arrow.circlepath"
        case .schedule: return "calendar.badge.clock"
        case .insights: return "lightbulb"
        }
    }
}

struct VolumeDiskTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 12)

            if viewModel.selectedVolume != nil {
                volumeTabPicker
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }

            Group {
                switch viewModel.selectedVolumeTab {
                case .overview:
                    OverviewTabView()
                case .breakdown:
                    BreakdownTabView()
                case .history:
                    ScanHistoryTabView()
                case .schedule:
                    ScanScheduleTabView()
                case .insights:
                    InsightsTabView()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Disk Analysis")
                    .font(.largeTitle.bold())
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 16) {
                headerBadges

                HStack(spacing: 8) {
                    if let volume = viewModel.selectedVolume {
                        if viewModel.isIndexed(volume) {
                            Button {
                                viewModel.scanSelectedVolume(mode: .fast)
                            } label: {
                                Label(
                                    viewModel.isScanning
                                        ? "Identifying…"
                                        : (viewModel.isAnalyzing ? "Analyzing…" : "Rescan"),
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isVolumeBusy(volume))

                            Button {
                                viewModel.scanSelectedVolume(mode: .deep)
                            } label: {
                                Label("Deep Scan", systemImage: "scope")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(viewModel.isVolumeBusy(volume))
                        } else {
                            Button {
                                viewModel.presentScanModePrompt(for: volume)
                            } label: {
                                Label(
                                    viewModel.isScanning ? "Identifying…" : "Scan Drive",
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isVolumeBusy(volume))
                        }

                        Button {
                            viewModel.scanFolderOnSelectedVolume()
                        } label: {
                            Label("Scan Folder…", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isVolumeBusy(volume))
                    }

                    VolumePickerMenu()
                }
            }
        }
    }

    private var headerSubtitle: String {
        if let volume = viewModel.selectedVolume {
            return "\(volume.name) — scan drives, review breakdowns, and get cleanup insights."
        }
        return "Scan drives, review breakdowns, and get cleanup insights."
    }

    @ViewBuilder
    private var headerBadges: some View {
        if let volume = viewModel.selectedVolume {
            SidebarDiskFreeSpaceBadge(volume: volume)
        }
    }

    private var volumeTabPicker: some View {
        DiskWiseIconTabBar(selection: $viewModel.selectedVolumeTab)
    }
}

struct VolumePickerMenu: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Menu {
            if !viewModel.internalVolumes.isEmpty {
                Section("Internal SSD") {
                    ForEach(viewModel.internalVolumes) { volume in
                        volumeMenuButton(volume)
                    }
                }
            }
            if !viewModel.externalVolumes.isEmpty {
                Section("External Drives") {
                    ForEach(viewModel.externalVolumes) { volume in
                        volumeMenuButton(volume)
                    }
                }
            }
            if viewModel.mountedVolumes.isEmpty {
                Button("Grant Permission") {
                    viewModel.presentFullDiskAccessOverlay()
                }
            }
            Divider()
            Button {
                viewModel.refreshDrivesAfterPermissionChange()
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedVolume?.isInternal == false ? "externaldrive.fill" : "internaldrive.fill")
                Text(viewModel.selectedVolume?.name ?? "Select Drive")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 220)
        }
        .menuStyle(.borderlessButton)
    }

    private func volumeMenuButton(_ volume: MountedVolume) -> some View {
        Button {
            viewModel.selectedVolumePath = volume.mountPath
            viewModel.selectVolume(volume)
        } label: {
            HStack {
                Text(volume.name)
                Spacer()
                if viewModel.selectedVolumePath == volume.mountPath {
                    Image(systemName: "checkmark")
                }
                Text(DiskWiseFormatters.bytes.string(fromByteCount: volume.freeSize) + " free")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

protocol DiskWiseTabRepresentable: Identifiable, CaseIterable, Hashable {
    var title: String { get }
    var icon: String { get }
}

extension VolumeDiskTab: DiskWiseTabRepresentable {}

struct DiskWiseIconTabBar<Tab: DiskWiseTabRepresentable>: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Tab.allCases), id: \.id) { tab in
                tabButton(tab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            Label(tab.title, systemImage: tab.icon)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OverviewTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.isScanning {
                    ScanProgressPanel()
                } else if viewModel.scanJustCompleted {
                    scanCompleteBanner
                } else if viewModel.isBackgroundWorkActive {
                    BackgroundScanBanner()
                } else if let volume = viewModel.selectedVolume,
                          viewModel.showsStorageGraphAnalysis,
                          let overview = viewModel.overview {
                    resultsHeader(volume: volume, overview: overview)
                } else if let volume = viewModel.selectedVolume, !viewModel.isIndexed(volume) {
                    UnindexedVolumeScanPanel(volume: volume)
                } else if let volume = viewModel.selectedVolume, viewModel.isIndexed(volume) {
                    idleScanPanel(volume: volume)
                } else {
                    WelcomeView()
                }
            }
            .padding(28)
        }
    }

    private var scanCompleteBanner: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Scan complete", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)

                Text("Disk usage has been indexed. Open Breakdown for charts, Apple Intelligence cleanup suggestions, and one-click actions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.openResultsTab()
                } label: {
                    Label("View Breakdown & Cleanup", systemImage: "chart.pie")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func idleScanPanel(volume: MountedVolume) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text(volume.name)
                    .font(.title2.bold())
                Text("Indexed data is available. Rescan to refresh usage or pick another folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        viewModel.scanSelectedVolume(mode: .fast)
                    } label: {
                        Label("Rescan \(volume.name)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        viewModel.scanSelectedVolume(mode: .deep)
                    } label: {
                        Label("Deep Scan", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        viewModel.scanFolderOnSelectedVolume()
                    } label: {
                        Label("Scan Folder…", systemImage: "folder.badge.plus")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resultsHeader(volume: MountedVolume, overview: StorageOverview) -> some View {
        Text("Drive Overview")
            .font(.title2.bold())
            .foregroundStyle(.secondary)

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
        }
    }
}

struct BreakdownTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.isBackgroundWorkActive && !viewModel.isScanning {
                    BackgroundScanBanner()
                }

                if let volume = viewModel.selectedVolume,
                   viewModel.showsStorageGraphAnalysis,
                   let overview = viewModel.overview {
                    breakdownHeader(volume: volume)

                    StorageResultsChartsSection(volume: volume, overview: overview)

                    if viewModel.isAnalyzing {
                        analyzingCleanupPlanBanner
                    }

                    if let report = viewModel.analysisReport {
                        StorageCleanupInsightsSection(report: report)
                    } else if viewModel.isAnalyzing {
                        preparingCleanupPlanPlaceholder
                    }

                    if viewModel.totalDuplicateSavings > 0 {
                        duplicatesCallToAction
                    }
                } else if viewModel.isScanning {
                    scanningPlaceholder
                } else {
                    emptyBreakdownPlaceholder
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

    private var analyzingCleanupPlanBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building your cleanup plan")
                        .font(.headline)
                    Text("Apple Intelligence is analyzing indexed files and grouping safe cleanup actions below the charts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preparingCleanupPlanPlaceholder: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Preparing Apple Intelligence cleanup suggestions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scanningPlaceholder: some View {
        ContentUnavailableView {
            Label("Scan in progress", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Switch to Overview to monitor progress, or wait here for the breakdown.")
        } actions: {
            Button("Go to Overview") {
                viewModel.selectedVolumeTab = .overview
            }
        }
    }

    private var emptyBreakdownPlaceholder: some View {
        ContentUnavailableView {
            Label("No breakdown yet", systemImage: "chart.pie")
        } description: {
            Text("Scan this drive to see category charts and storage distribution.")
        } actions: {
            if let volume = viewModel.selectedVolume {
                Button("Scan \(volume.name)") {
                    viewModel.requestScan(for: volume)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func breakdownHeader(volume: MountedVolume) -> some View {
        Text("Storage Breakdown")
            .font(.title2.bold())
            .foregroundStyle(.secondary)
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
                    Text("\(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.totalDuplicateSavings)) can be reclaimed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.openDuplicatesPane(review: true)
                } label: {
                    Label("Review Duplicates", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InsightsTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.isAnalyzing {
                    BackgroundScanBanner()
                }

                if viewModel.analysisReport != nil {
                    breakdownCleanupLink
                }

                if !viewModel.topConsumers.isEmpty {
                    topConsumersSection
                } else if viewModel.isScanning || viewModel.isAnalyzing {
                    ContentUnavailableView {
                        Label("Analysis in progress", systemImage: "lightbulb")
                    } description: {
                        Text("Top space consumers appear after the scan and storage analysis finish.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No insights yet", systemImage: "lightbulb")
                    } description: {
                        Text("Scan this drive to see top space consumers and ask follow-up questions.")
                    } actions: {
                        if let volume = viewModel.selectedVolume {
                            Button("Scan \(volume.name)") {
                                viewModel.requestScan(for: volume)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                GroupBox {
                    AskDiskWiseView()
                }
            }
            .padding(28)
        }
    }

    private var breakdownCleanupLink: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cleanup actions live on Breakdown")
                        .font(.headline)
                    Text("Apple Intelligence groups Safe to Clean, Review First, and Personal sections with Take Action buttons next to your storage charts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    viewModel.selectedVolumeTab = .breakdown
                } label: {
                    Label("Open Breakdown", systemImage: "chart.pie")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topConsumersSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Top Space Consumers", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                ForEach(viewModel.topConsumers) { consumer in
                    HStack {
                        Text(consumer.name)
                            .lineLimit(1)
                        Spacer()
                        Text(DiskWiseFormatters.bytes.string(fromByteCount: consumer.totalSize))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
