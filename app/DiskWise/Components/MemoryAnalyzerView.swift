import AIKit
import SwiftUI

struct MemoryAnalyzerView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var monitor = MemoryAnalyzerMonitor.shared

    @State private var memoryReliefTrigger = 0
    @State private var actionMessage: String?
    @State private var quitTargetName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let report = monitor.report {
                    memoryOverviewCard(report)
                    trendCard
                    persistentConsumersCard(report)
                    if let summary = report.aiSummary {
                        aiInsightsCard(summary)
                    }
                    recommendationsCard(report)
                } else {
                    loadingState
                }
            }
            .padding(28)
        }
        .onAppear {
            monitor.refreshConfiguration(from: viewModel.appSettings)
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
                quitApplication(named: name)
            }
            Button("Cancel", role: .cancel) {
                quitTargetName = nil
            }
        } message: { name in
            Text("Quit \(name)? Unsaved work may be lost.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Memory Analyzer")
                    .font(.largeTitle.bold())
                Text("Periodic memory monitoring with Apple Intelligence optimization tips.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitor.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
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
    private func aiInsightsCard(_ summary: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Apple Intelligence Insights")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Label("Optimization Analysis", systemImage: "brain.head.profile")
        }
    }

    @ViewBuilder
    private func recommendationsCard(_ report: MemoryAnalysisReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.recommendations) { recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: recommendation.actionKind))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
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
                    .padding(.vertical, 4)
                }
            }
        } label: {
            Label("Suggested Actions", systemImage: "bolt.fill")
        }
    }

    @ViewBuilder
    private func actionButton(for recommendation: MemoryActionRecommendation) -> some View {
        switch recommendation.actionKind {
        case .freeMemory:
            Button("Free Memory") {
                memoryReliefTrigger += 1
                Task {
                    let result = await SystemHealthMonitor.shared.freeUpMemory()
                    actionMessage = resultMessage(for: result)
                    monitor.captureNow()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .quitProcess, .restartApp:
            if let name = recommendation.targetProcessName {
                Button(recommendation.actionKind == .restartApp ? "Restart" : "Quit") {
                    quitTargetName = name
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .reduceTabs:
            if let name = recommendation.targetProcessName {
                Button("Focus App") {
                    activateApplication(named: name)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .informational:
            EmptyView()
        }
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

    private func resultMessage(for result: MemoryReliefResult) -> String {
        switch result {
        case .relieved(_, let message): return message
        case .improved(let message): return message
        case .noMeasurableChange(let message): return message
        case .requiresAdmin(let message): return message
        case .failed(let message): return message
        }
    }

    private func quitApplication(named name: String) {
        quitTargetName = nil
        let running = NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                || ($0.localizedName?.lowercased().contains(name.lowercased()) == true)
        }
        if let app = running {
            let terminated = app.terminate()
            actionMessage = terminated
                ? "Sent quit signal to \(name)."
                : "Could not quit \(name). It may ignore quit requests."
            monitor.captureNow()
        } else {
            actionMessage = "\(name) is not running as a user application."
        }
    }

    private func activateApplication(named name: String) {
        let running = NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                || ($0.localizedName?.lowercased().contains(name.lowercased()) == true)
        }
        running?.activate()
        actionMessage = "Brought \(name) to the front so you can close unused tabs."
    }
}
