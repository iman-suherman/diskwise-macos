import Foundation

public final class MemoryAnalysisEngine: @unchecked Sendable {
    private let consultant: AIConsultantService

    public init(consultant: AIConsultantService = AIConsultantService()) {
        self.consultant = consultant
    }

    public func updateConsultantConfiguration(_ configuration: AIProviderConfiguration) {
        consultant.updateConfiguration(configuration)
    }

    public func analyze(samples: [MemorySampleRecord]) async -> MemoryAnalysisReport {
        let base = buildRuleBasedReport(from: samples)
        let context = MemoryAnalysisContext(report: base, recentSamples: samples)
        let aiSummary = await consultant.analyzeMemory(context: context)
        return finalizedReport(base: base, aiSummary: aiSummary)
    }

    public func prepareReport(from samples: [MemorySampleRecord]) -> MemoryAnalysisReport {
        buildRuleBasedReport(from: samples)
    }

    public func fallbackSummary(for report: MemoryAnalysisReport) -> String {
        ruleBasedSummary(for: report)
    }

    public func streamMemorySummary(
        context: MemoryAnalysisContext,
        fallback: String
    ) -> AsyncThrowingStream<String, Error> {
        consultant.streamAnalyzeMemory(context: context, fallback: fallback)
    }

    public func streamMemoryRespond(
        to question: String,
        context: MemoryAnalysisContext
    ) -> AsyncThrowingStream<String, Error> {
        consultant.streamRespondMemory(to: question, context: context)
    }

    private func finalizedReport(base: MemoryAnalysisReport, aiSummary: String?) -> MemoryAnalysisReport {
        MemoryAnalysisReport(
            sampledAt: base.sampledAt,
            sampleCount: base.sampleCount,
            currentUsedPercent: base.currentUsedPercent,
            averageUsedPercent: base.averageUsedPercent,
            peakUsedPercent: base.peakUsedPercent,
            persistentConsumers: base.persistentConsumers,
            recommendations: base.recommendations,
            aiSummary: aiSummary ?? ruleBasedSummary(for: base)
        )
    }

    public func providerStatus() async -> AIProviderStatus {
        await consultant.providerStatus()
    }

    private func buildRuleBasedReport(from samples: [MemorySampleRecord]) -> MemoryAnalysisReport {
        guard !samples.isEmpty else {
            return MemoryAnalysisReport(
                sampledAt: Date(),
                sampleCount: 0,
                currentUsedPercent: 0,
                averageUsedPercent: 0,
                peakUsedPercent: 0,
                persistentConsumers: [],
                recommendations: [
                    MemoryActionRecommendation(
                        title: "Collecting memory samples",
                        detail: "DiskWise is monitoring memory in the background. Check back after a few minutes.",
                        actionKind: .informational,
                        priority: 0
                    ),
                ]
            )
        }

        let current = samples.last!
        let averageUsed = samples.map(\.usedPercent).reduce(0, +) / Double(samples.count)
        let peakUsed = samples.map(\.usedPercent).max() ?? current.usedPercent
        let persistentConsumers = aggregatePersistentConsumers(from: samples)
        var recommendations = buildRecommendations(
            currentUsedPercent: current.usedPercent,
            averageUsedPercent: averageUsed,
            peakUsedPercent: peakUsed,
            persistentConsumers: persistentConsumers
        )

        if recommendations.isEmpty {
            recommendations.append(
                MemoryActionRecommendation(
                    title: "Memory looks healthy",
                    detail: "No persistent heavy consumers detected. Keep monitoring while you work.",
                    actionKind: .informational,
                    priority: 0
                )
            )
        }

        return MemoryAnalysisReport(
            sampledAt: Date(),
            sampleCount: samples.count,
            currentUsedPercent: current.usedPercent,
            averageUsedPercent: averageUsed,
            peakUsedPercent: peakUsed,
            persistentConsumers: persistentConsumers,
            recommendations: recommendations.sorted { $0.priority > $1.priority }
        )
    }

    private func aggregatePersistentConsumers(from samples: [MemorySampleRecord]) -> [MemoryProcessProfile] {
        var totals: [String: (total: Int64, peak: Int64, count: Int)] = [:]

        for sample in samples {
            for process in sample.topProcesses {
                var entry = totals[process.name, default: (0, 0, 0)]
                entry.total += process.memoryBytes
                entry.peak = max(entry.peak, process.memoryBytes)
                entry.count += 1
                totals[process.name] = entry
            }
        }

        return totals
            .map { name, stats in
                MemoryProcessProfile(
                    name: name,
                    averageMemoryBytes: stats.count > 0 ? stats.total / Int64(stats.count) : 0,
                    peakMemoryBytes: stats.peak,
                    sampleCount: stats.count
                )
            }
            .filter { $0.averageMemoryBytes >= 512 * 1024 * 1024 }
            .sorted { $0.averageMemoryBytes > $1.averageMemoryBytes }
            .prefix(12)
            .map { $0 }
    }

    private func buildRecommendations(
        currentUsedPercent: Double,
        averageUsedPercent: Double,
        peakUsedPercent: Double,
        persistentConsumers: [MemoryProcessProfile]
    ) -> [MemoryActionRecommendation] {
        var items: [MemoryActionRecommendation] = []

        if currentUsedPercent >= 80 || peakUsedPercent >= 88 {
            items.append(
                MemoryActionRecommendation(
                    title: "Free inactive memory",
                    detail: "Memory is under pressure (\(String(format: "%.0f", currentUsedPercent))% in use). Purging inactive cache can help immediately.",
                    actionKind: .freeMemory,
                    priority: 90
                )
            )
        }

        if averageUsedPercent >= 75 {
            items.append(
                MemoryActionRecommendation(
                    title: "Reduce background load",
                    detail: "Average memory use is \(String(format: "%.0f", averageUsedPercent))% across recent samples. Quit apps you are not actively using.",
                    actionKind: .informational,
                    priority: 70
                )
            )
        }

        for profile in persistentConsumers.prefix(5) {
            let avgGB = Double(profile.averageMemoryBytes) / 1_073_741_824
            let nameLower = profile.name.lowercased()

            if MemoryProcessRules.isDiskWise(profile.name) {
                if profile.averageMemoryBytes >= 1_500 * 1024 * 1024, profile.sampleCount >= 2 {
                    items.append(
                        MemoryActionRecommendation(
                            title: "DiskWise memory is elevated",
                            detail: MemoryProcessRules.highMemoryUsageDetail(
                                for: profile.name,
                                averageGB: avgGB,
                                sampleCount: profile.sampleCount
                            ),
                            actionKind: .informational,
                            priority: 55
                        )
                    )
                }
                continue
            }

            if nameLower.contains("chrome") || nameLower.contains("safari") || nameLower.contains("firefox") || nameLower.contains("edge") {
                items.append(
                    MemoryActionRecommendation(
                        title: "Trim \(profile.name) tabs",
                        detail: "\(profile.name) averages \(String(format: "%.1f", avgGB)) GB across \(profile.sampleCount) samples. Close unused tabs or enable tab discarding.",
                        actionKind: .reduceTabs,
                        targetProcessName: profile.name,
                        priority: 80
                    )
                )
                continue
            }

            if profile.averageMemoryBytes >= 2 * 1024 * 1024 * 1024, profile.sampleCount >= 2 {
                items.append(
                    MemoryActionRecommendation(
                        title: "Restart \(profile.name)",
                        detail: MemoryProcessRules.highMemoryUsageDetail(
                            for: profile.name,
                            averageGB: avgGB,
                            sampleCount: profile.sampleCount
                        ),
                        actionKind: .restartApp,
                        targetProcessName: profile.name,
                        priority: 75
                    )
                )
                continue
            }

            if profile.averageMemoryBytes >= 1_500 * 1024 * 1024, profile.sampleCount >= 3 {
                items.append(
                    MemoryActionRecommendation(
                        title: "Quit \(profile.name) when idle",
                        detail: "\(profile.name) appears in \(profile.sampleCount) samples averaging \(String(format: "%.1f", avgGB)) GB.",
                        actionKind: .quitProcess,
                        targetProcessName: profile.name,
                        priority: 65
                    )
                )
            }
        }

        return items
    }

    private func ruleBasedSummary(for report: MemoryAnalysisReport) -> String {
        if report.persistentConsumers.isEmpty {
            return "DiskWise is collecting memory samples. No persistent heavy consumers have been identified yet."
        }

        let top = report.persistentConsumers.prefix(3)
            .map { "- **\($0.name)** — avg \(formattedMemory($0.averageMemoryBytes))" }
            .joined(separator: "\n")

        if report.currentUsedPercent >= 80 {
            return """
            ## Memory under pressure

            **Current:** \(String(format: "%.1f", report.currentUsedPercent))%
            **Average:** \(String(format: "%.1f", report.averageUsedPercent))%
            **Peak:** \(String(format: "%.1f", report.peakUsedPercent))%

            ## Persistent memory consumers

            \(top)

            ## Recommendations

            - **Free inactive memory:** Memory is under pressure. Purging inactive cache can help immediately.
            """
        }

        return """
        ## Memory overview

        **Current:** \(String(format: "%.1f", report.currentUsedPercent))%
        **Average:** \(String(format: "%.1f", report.averageUsedPercent))%
        **Peak:** \(String(format: "%.1f", report.peakUsedPercent))%

        ## Persistent memory consumers

        \(top)

        ## Better computing habits

        Tip 1: Close unused apps — Quit apps you are not actively using.
        Tip 2: Control browser tabs — Each tab uses RAM; close tabs you no longer need.
        Tip 3: Restart heavy apps — Restart memory-heavy apps that have been open for days.
        """
    }

    private func formattedMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
