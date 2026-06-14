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
        Analyze periodic memory samples and persistent process profiles.
        Explain which apps usually consume the most RAM and why.
        Suggest practical, safe ways to run apps more efficiently on this Mac.
        Recommend quitting or restarting specific apps only when data supports it.
        Use plain language, 2-4 short paragraphs, and mention the top memory consumers by name.
        Do not recommend disabling macOS system services.
        """
    }
}
