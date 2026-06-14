import SwiftUI
import Charts
import DatabaseKit
import AIKit
import DiskScannerKit

enum VolumeDiskTab: String, CaseIterable, Identifiable {
    case scanning
    case results
    case recommendations
    case aiAnalysis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanning: return "Scanning"
        case .results: return "Results"
        case .recommendations: return "Recommendations"
        case .aiAnalysis: return "AI Analysis"
        }
    }

    var icon: String {
        switch self {
        case .scanning: return "arrow.triangle.2.circlepath"
        case .results: return "chart.pie"
        case .recommendations: return "lightbulb"
        case .aiAnalysis: return "sparkles"
        }
    }
}

struct VolumeDiskTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedVolume != nil {
                volumeTabPicker
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }

            Group {
                switch viewModel.selectedVolumeTab {
                case .scanning:
                    ScanningTabView()
                case .results:
                    ResultsTabView()
                case .recommendations:
                    RecommendationsTabView()
                case .aiAnalysis:
                    AIAnalysisTabView()
                }
            }
        }
    }

    private var volumeTabPicker: some View {
        Picker("Disk section", selection: $viewModel.selectedVolumeTab) {
            ForEach(VolumeDiskTab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 640)
    }
}

struct ScanningTabView: View {
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

                Text("Disk usage has been indexed. Review the breakdown and recommendations in the other tabs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.openResultsTab()
                } label: {
                    Label("View Results", systemImage: "chart.pie")
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
                        viewModel.scanSelectedVolume()
                    } label: {
                        Label("Rescan \(volume.name)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)

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
}

struct ResultsTabView: View {
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
                    resultsHeader(volume: volume, overview: overview)

                    StorageResultsChartsSection(volume: volume, overview: overview)

                    if viewModel.totalDuplicateSavings > 0 || viewModel.isFindingDuplicates {
                        duplicatesCallToAction
                    }

                    if !viewModel.topConsumers.isEmpty {
                        topConsumersSection
                    }
                } else if viewModel.isScanning {
                    scanningPlaceholder
                } else {
                    emptyResultsPlaceholder
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

    private var scanningPlaceholder: some View {
        ContentUnavailableView {
            Label("Scan in progress", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Switch to the Scanning tab to monitor progress, or wait here for results.")
        } actions: {
            Button("Go to Scanning") {
                viewModel.selectedVolumeTab = .scanning
            }
        }
    }

    private var emptyResultsPlaceholder: some View {
        ContentUnavailableView {
            Label("No scan results yet", systemImage: "chart.pie")
        } description: {
            Text("Scan this drive to see storage breakdown and top space consumers.")
        } actions: {
            if let volume = viewModel.selectedVolume {
                Button("Scan \(volume.name)") {
                    viewModel.scan(volume: volume)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func resultsHeader(volume: MountedVolume, overview: StorageOverview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(volume.name)
                .font(.largeTitle.bold())
            Text("Storage Results")
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
                    Text("\(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.totalDuplicateSavings)) can be reclaimed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.openDuplicatesPane()
                } label: {
                    Label("Review Duplicates", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Space Consumers")
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
    }
}

struct RecommendationsTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.isAnalyzing {
                    BackgroundScanBanner()
                }

                if let report = viewModel.analysisReport {
                    storageIntelligenceSection(report: report)
                    recommendationsSection(report: report)
                } else if viewModel.isScanning || viewModel.isAnalyzing {
                    ContentUnavailableView {
                        Label("Analysis in progress", systemImage: "lightbulb")
                    } description: {
                        Text("Recommendations appear after the scan and storage analysis finish.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "lightbulb")
                    } description: {
                        Text("Scan this drive to generate cleanup recommendations.")
                    } actions: {
                        if let volume = viewModel.selectedVolume {
                            Button("Scan \(volume.name)") {
                                viewModel.scan(volume: volume)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(28)
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
                    Text(viewModel.aiAnalysisSummary)
                        .font(.body)
                        .foregroundStyle(.secondary)
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
}

struct AIAnalysisTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        AskDiskWiseView()
    }
}
