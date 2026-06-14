import Foundation

enum MemoryContextFormatter {
    static func format(_ context: MemoryAnalysisContext) -> String {
        let report = context.report
        let bytes = ByteCountFormatter()
        bytes.countStyle = .memory

        let consumers = report.persistentConsumers
            .prefix(10)
            .map { profile in
                "- \(profile.name): avg \(bytes.string(fromByteCount: profile.averageMemoryBytes)), peak \(bytes.string(fromByteCount: profile.peakMemoryBytes)) (\(profile.sampleCount) samples)"
            }
            .joined(separator: "\n")

        let recommendations = report.recommendations
            .prefix(8)
            .map { "- \($0.title): \($0.detail)" }
            .joined(separator: "\n")

        let trend = context.recentSamples.suffix(12)
            .map { String(format: "%.1f%%", $0.usedPercent) }
            .joined(separator: " → ")

        return """
        DiskWise memory analysis (\(report.sampleCount) periodic samples):
        Current memory use: \(String(format: "%.1f", report.currentUsedPercent))%
        Average over samples: \(String(format: "%.1f", report.averageUsedPercent))%
        Peak observed: \(String(format: "%.1f", report.peakUsedPercent))%
        Recent trend: \(trend.isEmpty ? "collecting samples" : trend)

        Persistent memory consumers:
        \(consumers.isEmpty ? "None above threshold yet." : consumers)

        Rule-based recommendations:
        \(recommendations.isEmpty ? "No urgent actions." : recommendations)
        """
    }

    static func analysisInstructions() -> String {
        """
        You are DiskWise, a privacy-first macOS performance consultant.
        Analyze the current memory state from periodic samples and persistent process profiles.
        Explain which apps usually consume the most RAM and why, based on the latest data.
        Suggest practical habits for using this Mac more efficiently — fewer background apps, browser tab discipline, restart cadence, and when to free inactive memory.
        Recommend quitting or restarting specific apps only when the sample data supports it.
        Do not recommend disabling macOS system services.
        Format replies with Markdown.
        Use blank lines between paragraphs and sections — put a carriage return between each paragraph.
        Put each bullet or numbered step on its own line with a blank line before each list.
        Use ## headings when covering multiple topics, each on its own line with a blank line above.
        Never run multiple sections together in one paragraph.
        Include a short ## Better computing habits section with 2-4 concrete tips for this Mac.
        """
    }
}
