import AIKit
import SwiftUI

enum MemoryAnalyzerScrollTarget {
    static let suggestedActions = "memory-analyzer-suggested-actions"
}

struct MemoryAnalyzerView: View {
    var embeddedInOptimization: Bool = false

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var monitor = MemoryAnalyzerMonitor.shared

    @State private var actionMessage: String?
    @State private var quitTargetName: String?

    var body: some View {
        Group {
            if embeddedInOptimization {
                embeddedContent
            } else {
                ScrollView {
                    embeddedContent
                        .padding(28)
                }
            }
        }
        .onAppear {
            guard !embeddedInOptimization else { return }
            monitor.applySettings(viewModel.appSettings)
            if monitor.report == nil {
                monitor.captureNow()
            }
        }
        .alert("Memory Action", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .alert(
            "Quit App?",
            isPresented: Binding(
                get: { quitTargetName != nil },
                set: { if !$0 { quitTargetName = nil } }
            ),
            presenting: quitTargetName
        ) { name in
            Button("Quit", role: .destructive) {
                Task { await performQuit(named: name) }
            }
            Button("Cancel", role: .cancel) {
                quitTargetName = nil
            }
        } message: { name in
            Text("Quit \(name)? Unsaved work may be lost.")
        }
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !embeddedInOptimization {
                header
            }

            if let report = monitor.report {
                memoryOverviewCard(report)
                trendCard
                persistentConsumersCard(report)
                if !embeddedInOptimization,
                   monitor.isStreamingAISummary || report.aiSummary != nil {
                    let summaryText = monitor.isStreamingAISummary
                        ? monitor.streamingAISummary
                        : (report.aiSummary ?? "")
                    aiInsightsCard(summaryText, report: report)
                }
                recommendationsCard(report)
            } else {
                loadingState
            }
        }
    }

    private func sectionHeading(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.title2.bold())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Memory Analyzer")
                    .font(.largeTitle.bold())
                Text("Runs in the background with periodic Apple Intelligence analysis and actionable notifications.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitor.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
            }

            if monitor.isRunning {
                Label("Monitoring", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Button {
                monitor.captureNow()
            } label: {
                Label("Sample Now", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)

            Button {
                monitor.refreshAIAnalysis()
            } label: {
                Label("Re-analyze", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(monitor.isAnalyzing || monitor.samples.count < 2)
        }
    }

    private var loadingState: some View {
        ContentUnavailableView(
            "Collecting memory samples",
            systemImage: "memorychip",
            description: Text("DiskWise samples memory every 20–30 seconds. The first analysis appears after a few samples.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private func memoryOverviewCard(_ report: MemoryAnalysisReport) -> some View {
        GroupBox {
            HStack(spacing: 24) {
                memoryGauge(
                    title: "Current",
                    percent: report.currentUsedPercent,
                    color: pressureColor(report.currentUsedPercent)
                )
                memoryGauge(
                    title: "Average",
                    percent: report.averageUsedPercent,
                    color: pressureColor(report.averageUsedPercent)
                )
                memoryGauge(
                    title: "Peak",
                    percent: report.peakUsedPercent,
                    color: pressureColor(report.peakUsedPercent)
                )

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Label("\(report.sampleCount) samples", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastSampleAt = monitor.lastSampleAt {
                        Text("Last sample \(lastSampleAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let lastAIAnalysisAt = monitor.lastAIAnalysisAt {
                        Text("Last AI analysis \(lastAIAnalysisAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Analysis via \(monitor.aiProviderLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } label: {
            Label("Memory Pressure", systemImage: "memorychip")
        }
    }

    private func memoryGauge(title: String, percent: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, percent / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent.rounded()))%")
                    .font(.title3.weight(.bold))
            }
            .frame(width: 72, height: 72)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var trendCard: some View {
        GroupBox {
            if monitor.samples.count >= 2 {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(monitor.samples.suffix(24).enumerated()), id: \.offset) { _, sample in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(pressureColor(sample.usedPercent).opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, CGFloat(sample.usedPercent) * 1.2))
                            .help("\(String(format: "%.1f", sample.usedPercent))% at \(sample.timestamp.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .frame(height: 120, alignment: .bottom)
            } else {
                Text("Trend chart appears after more samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Recent Trend", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    @ViewBuilder
    private func persistentConsumersCard(_ report: MemoryAnalysisReport) -> some View {
        GroupBox {
            if report.persistentConsumers.isEmpty {
                Text("No persistent heavy consumers detected yet. Keep DiskWise open while you work.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(report.persistentConsumers) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(profile.sampleCount) samples · peak \(DiskWiseFormatters.bytes.string(fromByteCount: profile.peakMemoryBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DiskWiseFormatters.bytes.string(fromByteCount: profile.averageMemoryBytes))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 8)
                        if profile.id != report.persistentConsumers.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Label("Usual Memory Consumers", systemImage: "list.bullet.rectangle")
        }
    }

    @ViewBuilder
    private func aiInsightsCard(_ summary: String, report: MemoryAnalysisReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Apple Intelligence Insights")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if monitor.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if monitor.isStreamingAISummary {
                    MemoryInsightStreamingView(
                        text: monitor.streamingAISummary,
                        isStreaming: monitor.isAnalyzing
                    )
                } else {
                    MemoryInsightContentView(
                        text: summary,
                        report: report,
                        onPerformAction: performInsightAction
                    )
                }

                if !monitor.isStreamingAISummary {
                    Divider()
                    MemoryInsightChatView(report: report, monitor: monitor)
                }
            }
        } label: {
            Label("Optimization Analysis", systemImage: "brain.head.profile")
        }
    }

    @ViewBuilder
    private func optimizationActionRow(_ recommendation: MemoryActionRecommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: recommendation.actionKind))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                Text(recommendation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            actionButton(for: recommendation)
        }
    }

    @ViewBuilder
    private func recommendationsCard(_ report: MemoryAnalysisReport) -> some View {
        let recommendations = monitor.actionableRecommendations
        if !recommendations.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(recommendations) { recommendation in
                        optimizationActionRow(recommendation)
                            .padding(.vertical, 4)
                    }
                }
            } label: {
                Label("Suggested Actions", systemImage: "bolt.fill")
            }
            .id(MemoryAnalyzerScrollTarget.suggestedActions)
        }
    }

    @ViewBuilder
    private func actionButton(for recommendation: MemoryActionRecommendation) -> some View {
        if let title = MemoryActionExecutor.actionTitle(for: recommendation) {
            if recommendation.actionKind == .freeMemory {
                Button(title) {
                    performRecommendation(recommendation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(title) {
                    performRecommendation(recommendation)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func performInsightAction(_ recommendation: MemoryActionRecommendation) {
        performRecommendation(recommendation)
    }

    private func performRecommendation(_ recommendation: MemoryActionRecommendation) {
        if recommendation.actionKind == .quitProcess {
            quitTargetName = recommendation.targetProcessName
            return
        }
        Task {
            actionMessage = await MemoryActionExecutor.perform(recommendation)
            monitor.captureNow()
        }
    }

    private func performQuit(named name: String) async {
        quitTargetName = nil
        actionMessage = await MemoryActionExecutor.perform(
            kind: .quitProcess,
            targetProcessName: name
        )
        monitor.captureNow()
    }

    private func icon(for kind: MemoryActionKind) -> String {
        switch kind {
        case .freeMemory: return "arrow.up.circle.fill"
        case .quitProcess: return "xmark.app.fill"
        case .restartApp: return "arrow.clockwise.circle.fill"
        case .reduceTabs: return "safari"
        case .informational: return "info.circle"
        }
    }

    private func pressureColor(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

struct AppleIntelligenceInsightsView: View {
    @ObservedObject private var monitor = MemoryAnalyzerMonitor.shared

    @State private var actionMessage: String?
    @State private var quitTargetName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeading

            if let report = monitor.report {
                if monitor.isStreamingAISummary || report.aiSummary != nil {
                    let summaryText = monitor.isStreamingAISummary
                        ? monitor.streamingAISummary
                        : (report.aiSummary ?? "")
                    optimizationAnalysisCard(summaryText, report: report)
                } else {
                    awaitingAnalysisState
                }
            } else {
                collectingSamplesState
            }
        }
        .alert("Memory Action", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .alert(
            "Quit App?",
            isPresented: Binding(
                get: { quitTargetName != nil },
                set: { if !$0 { quitTargetName = nil } }
            ),
            presenting: quitTargetName
        ) { name in
            Button("Quit", role: .destructive) {
                Task { await performQuit(named: name) }
            }
            Button("Cancel", role: .cancel) {
                quitTargetName = nil
            }
        } message: { name in
            Text("Quit \(name)? Unsaved work may be lost.")
        }
    }

    private var sectionHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Apple Intelligence", systemImage: "sparkles")
                .font(.title2.bold())
            Text("Optimization analysis and follow-up questions powered by on-device AI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var collectingSamplesState: some View {
        ContentUnavailableView(
            "Collecting memory samples",
            systemImage: "sparkles",
            description: Text("DiskWise needs a few memory samples before Apple Intelligence can analyze your usage patterns.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var awaitingAnalysisState: some View {
        ContentUnavailableView(
            "No analysis yet",
            systemImage: "sparkles",
            description: Text("Use Re-analyze in the header to generate your first Apple Intelligence insights.")
        )
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    @ViewBuilder
    private func optimizationAnalysisCard(_ summary: String, report: MemoryAnalysisReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Apple Intelligence Insights")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if monitor.isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("via \(monitor.aiProviderLabel)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if monitor.isStreamingAISummary {
                    MemoryInsightStreamingView(
                        text: monitor.streamingAISummary,
                        isStreaming: monitor.isAnalyzing
                    )
                } else {
                    MemoryInsightContentView(
                        text: summary,
                        report: report,
                        onPerformAction: performInsightAction
                    )
                }

                if !monitor.isStreamingAISummary {
                    Divider()
                    MemoryInsightChatView(report: report, monitor: monitor)
                }
            }
        } label: {
            Label("Optimization Analysis", systemImage: "brain.head.profile")
        }
    }

    private func performInsightAction(_ recommendation: MemoryActionRecommendation) {
        if recommendation.actionKind == .quitProcess {
            quitTargetName = recommendation.targetProcessName
            return
        }
        Task {
            actionMessage = await MemoryActionExecutor.perform(recommendation)
            monitor.captureNow()
        }
    }

    private func performQuit(named name: String) async {
        quitTargetName = nil
        actionMessage = await MemoryActionExecutor.perform(
            kind: .quitProcess,
            targetProcessName: name
        )
        monitor.captureNow()
    }
}
