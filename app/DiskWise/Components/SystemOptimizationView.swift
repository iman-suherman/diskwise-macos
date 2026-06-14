import SwiftUI

enum SystemOptimizationTab: String, CaseIterable, Identifiable {
    case systemStatus
    case memoryAnalyzer
    case processUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemStatus: return "System Status"
        case .memoryAnalyzer: return "Memory Analyzer"
        case .processUsage: return "Process Usage"
        }
    }

    var icon: String {
        switch self {
        case .systemStatus: return "heart.text.square"
        case .memoryAnalyzer: return "memorychip"
        case .processUsage: return "cpu"
        }
    }
}

struct SystemOptimizationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var healthMonitor = SystemHealthMonitor.shared
    @ObservedObject private var memoryMonitor = MemoryAnalyzerMonitor.shared

    @State private var selectedTab: SystemOptimizationTab = .systemStatus

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 12)

            Picker("System section", selection: $selectedTab) {
                ForEach(SystemOptimizationTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 720)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .systemStatus:
                        SystemStatusView(
                            embeddedInOptimization: true,
                            displaySection: .summary
                        )
                    case .memoryAnalyzer:
                        MemoryAnalyzerView(embeddedInOptimization: true)
                    case .processUsage:
                        SystemStatusView(
                            embeddedInOptimization: true,
                            displaySection: .processUsage
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Optimization")
                    .font(.largeTitle.bold())
                Text("Health score, live metrics, and AI recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 16) {
                scoreBadges

                HStack(spacing: 8) {
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
        }
    }

    @ViewBuilder
    private var scoreBadges: some View {
        if let score = healthMonitor.snapshot?.healthScore {
            SidebarLabelScoreBadge(
                label: "Health",
                score: "\(score)",
                color: healthScoreColor(score)
            )
        }
    }

    private func healthScoreColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
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

struct SidebarStackedScoreBadges: View {
    let healthScore: Int?
    let healthColor: (Int) -> Color

    var body: some View {
        if let healthScore {
            SidebarLabelScoreBadge(
                label: "Health",
                score: "\(healthScore)",
                color: healthColor(healthScore)
            )
        }
    }
}
