import AIKit
import AppKit
import MaintenanceKit
import SwiftUI

struct StartupAppsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var monitor = StartupAppsMonitor.shared

    @State private var filterSource: StartupAppSource?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if monitor.isScanning && monitor.scanResult == nil {
                        loadingState
                    } else if let report = monitor.report {
                        summarySection(report)
                        filterBar(report)
                        itemList(report)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            monitor.refreshConfiguration(from: viewModel.appSettings)
            monitor.scanAndAnalyze()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup Apps")
                    .font(.largeTitle.bold())
                Text("Login items, Dock apps, and launch agents with Apple Intelligence guidance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if monitor.isScanning || monitor.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    monitor.openLoginItemsSettings()
                } label: {
                    Label("Login Items Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                Button {
                    monitor.scanAndAnalyze(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(monitor.isScanning)

                Button {
                    monitor.reanalyze()
                } label: {
                    Label("Re-analyze", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(monitor.isScanning || monitor.isAnalyzing || (monitor.scanResult?.items.isEmpty ?? true))
            }
        }
    }

    private var loadingState: some View {
        ContentUnavailableView {
            ProgressView()
                .controlSize(.large)
        } description: {
            Text("Scanning startup apps and running Apple Intelligence analysis…")
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No startup apps found",
            systemImage: "power.circle",
            description: Text("DiskWise did not detect login items, Dock startup apps, or launch agents.")
        )
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    @ViewBuilder
    private func summarySection(_ report: StartupAppsAnalysisReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Overview", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("via \(monitor.aiProviderLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 16) {
                    summaryBadge(
                        count: report.items.filter { $0.source == .loginItem }.count,
                        label: "Open at Login",
                        icon: "power.circle"
                    )
                    summaryBadge(
                        count: report.items.filter { $0.source == .dockPinned }.count,
                        label: "Dock",
                        icon: "dock.rectangle"
                    )
                    summaryBadge(
                        count: report.items.filter { $0.source == .launchAgent || $0.source == .backgroundItem }.count,
                        label: "Background",
                        icon: "gearshape.2"
                    )
                }

                if monitor.isStreamingAnalysis, !monitor.streamingAnalysis.isEmpty {
                    DiskWiseMarkdownText(text: monitor.streamingAnalysis, font: .callout, format: .memoryInsight)
                } else if let summary = report.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func summaryBadge(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label("\(count)", systemImage: icon)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func filterBar(_ report: StartupAppsAnalysisReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", source: nil, count: report.items.count)
                ForEach(StartupAppSource.allCases) { source in
                    let count = report.items.filter { $0.source == source }.count
                    if count > 0 {
                        filterChip(title: source.displayName, source: source, count: count)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, source: StartupAppSource?, count: Int) -> some View {
        let isSelected = filterSource == source
        return Button {
            filterSource = source
        } label: {
            Text("\(title) (\(count))")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private func itemList(_ report: StartupAppsAnalysisReport) -> some View {
        let items = filteredItems(from: report)
        return LazyVStack(spacing: 12) {
            ForEach(items) { item in
                StartupAppRow(
                    item: item,
                    analysis: report.analysis(for: item),
                    isAnalyzing: monitor.isAnalyzing && monitor.report?.analysis(for: item) == nil
                )
            }
        }
    }

    private func filteredItems(from report: StartupAppsAnalysisReport) -> [StartupAppItem] {
        guard let filterSource else { return report.items }
        return report.items.filter { $0.source == filterSource }
    }
}

private struct StartupAppRow: View {
    let item: StartupAppItem
    let analysis: StartupAppAnalysis?
    let isAnalyzing: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    appIcon

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline)
                            if item.isHidden {
                                Text("Hidden")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }
                        }

                        Label(item.source.displayName, systemImage: item.source.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let path = item.path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack(spacing: 8) {
                            if item.alsoInDock {
                                tagLabel("In Dock", icon: "dock.rectangle")
                            }
                            if item.alsoLoginItem && item.source != .loginItem {
                                tagLabel("Open at Login", icon: "power.circle")
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if let analysis {
                        recommendationBadge(analysis.recommendation)
                    } else if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let analysis {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(analysis.analysis)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if isAnalyzing {
                    Text("Analyzing with Apple Intelligence…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = item.path, path.hasSuffix(".app") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 40, height: 40)
        } else {
            Image(systemName: item.source.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
        }
    }

    private func recommendationBadge(_ recommendation: StartupAppRecommendation) -> some View {
        let color: Color = switch recommendation {
        case .keepAtLogin: .green
        case .disableAtLogin: .red
        case .optional: .orange
        }

        return VStack(spacing: 4) {
            Image(systemName: recommendation.icon)
                .foregroundStyle(color)
            Text(recommendation.displayName)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
        }
        .frame(width: 88)
    }

    private func tagLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
