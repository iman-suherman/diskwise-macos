import SwiftUI

enum SystemOptimizationTab: String, CaseIterable, Identifiable {
    case systemStatus
    case memoryAnalyzer
    case appleIntelligence
    case processUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemStatus: return "System Status"
        case .memoryAnalyzer: return "Memory Analyzer"
        case .appleIntelligence: return "Apple Intelligence"
        case .processUsage: return "Process Usage"
        }
    }

    var icon: String {
        switch self {
        case .systemStatus: return "heart.text.square"
        case .memoryAnalyzer: return "memorychip"
        case .appleIntelligence: return "sparkles"
        case .processUsage: return "cpu"
        }
    }
}

extension SystemOptimizationTab: DiskWiseTabRepresentable {}

struct SystemOptimizationNavigationRequest: Equatable {
    let id = UUID()
    let tab: SystemOptimizationTab
    let scrollAnchor: String?

    static func == (lhs: SystemOptimizationNavigationRequest, rhs: SystemOptimizationNavigationRequest) -> Bool {
        lhs.id == rhs.id
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

            DiskWiseIconTabBar(selection: $selectedTab)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

            ScrollViewReader { proxy in
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
                        case .appleIntelligence:
                            AppleIntelligenceInsightsView()
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
                .onAppear {
                    applyNavigationRequest(viewModel.systemOptimizationNavigationRequest, proxy: proxy)
                }
                .onChange(of: viewModel.systemOptimizationNavigationRequest?.id) { _, _ in
                    applyNavigationRequest(viewModel.systemOptimizationNavigationRequest, proxy: proxy)
                }
            }
        }
        .onAppear {
            healthMonitor.refreshDetailed()
            memoryMonitor.applySettings(viewModel.appSettings)
            if memoryMonitor.report == nil {
                memoryMonitor.captureNow()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .appleIntelligence {
                memoryMonitor.releasePresentationMemory()
                viewModel.releaseIdleOptimizationMemory()
            }
        }
        .onDisappear {
            healthMonitor.refresh(processLimit: 5)
            memoryMonitor.releasePresentationMemory()
            viewModel.releaseIdleOptimizationMemory()
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
                label: SystemHealthMonitorCore.healthConditionLabel(for: score),
                score: "\(score)",
                color: healthScoreColor(score)
            )
        }
    }

    private func healthScoreColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func applyNavigationRequest(
        _ request: SystemOptimizationNavigationRequest?,
        proxy: ScrollViewProxy
    ) {
        guard let request else { return }
        selectedTab = request.tab
        viewModel.systemOptimizationNavigationRequest = nil
        guard let anchor = request.scrollAnchor else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation {
                proxy.scrollTo(anchor, anchor: .top)
            }
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
            .accessibilityLabel("\(label) \(score)")
    }
}

struct SidebarStackedScoreBadges: View {
    let healthScore: Int?
    let healthColor: (Int) -> Color

    var body: some View {
        if let healthScore {
            SidebarLabelScoreBadge(
                label: SystemHealthMonitorCore.healthConditionLabel(for: healthScore),
                score: "\(healthScore)",
                color: healthColor(healthScore)
            )
        }
    }
}
