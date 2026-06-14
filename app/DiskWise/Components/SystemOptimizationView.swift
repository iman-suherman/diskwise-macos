import SwiftUI

struct SystemOptimizationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var healthMonitor = SystemHealthMonitor.shared
    @ObservedObject private var memoryMonitor = MemoryAnalyzerMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                SystemStatusView(embeddedInOptimization: true)
                MemoryAnalyzerView(embeddedInOptimization: true)
            }
            .padding(28)
        }
        .onAppear {
            healthMonitor.refreshDetailed()
            memoryMonitor.applySettings(viewModel.appSettings)
            if memoryMonitor.report == nil {
                memoryMonitor.captureNow()
            }
        }
        .onDisappear {
            healthMonitor.refresh(processLimit: 5)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Optimization")
                    .font(.largeTitle.bold())
                Text("Health score, live metrics, memory monitoring, and Apple Intelligence recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            scoreBadges

            if memoryMonitor.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
            }

            if memoryMonitor.isRunning {
                Label("Monitoring", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Button {
                healthMonitor.refreshDetailed()
                memoryMonitor.captureNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                memoryMonitor.refreshAIAnalysis()
            } label: {
                Label("Re-analyze", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(memoryMonitor.isAnalyzing || memoryMonitor.samples.count < 2)
        }
    }

    @ViewBuilder
    private var scoreBadges: some View {
        HStack(spacing: 10) {
            if let score = healthMonitor.snapshot?.healthScore {
                SidebarLabelScoreBadge(
                    label: "Health",
                    score: "\(score)",
                    color: healthScoreColor(score)
                )
            }
            if let report = memoryMonitor.report {
                SidebarLabelScoreBadge(
                    label: "Mem",
                    score: "\(Int(report.currentUsedPercent.rounded()))%",
                    color: memoryPressureColor(report.currentUsedPercent)
                )
            }
        }
    }

    private func healthScoreColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func memoryPressureColor(_ percent: Double) -> Color {
        switch percent {
        case ..<60: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }
}

struct SidebarLabelScoreBadge: View {
    let label: String
    let score: String
    let color: Color

    var body: some View {
        Text("\(label) (\(score))")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel("\(label) score \(score)")
    }
}
