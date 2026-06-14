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
        return MemoryAnalysisReport(
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
                        detail: "\(profile.name) consistently uses \(String(format: "%.1f", avgGB)) GB. Restarting can clear memory leaks.",
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

            Memory is at **\(String(format: "%.0f", report.currentUsedPercent))%**. The usual consumers are:

            \(top)

            Consider freeing inactive memory or quitting apps you are not using.
            """
        }

        return """
        ## Memory overview

        Based on **\(report.sampleCount) samples**, average use is **\(String(format: "%.0f", report.averageUsedPercent))%** with a peak of **\(String(format: "%.0f", report.peakUsedPercent))%**.

        ## Top consumers

        \(top)

        ## Better computing habits

        - Close apps you are not actively using
        - Keep browser tabs under control — each tab uses RAM
        - Restart memory-heavy apps that have been open for days
        """
    }

    private func formattedMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
