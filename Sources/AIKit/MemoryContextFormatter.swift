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
        Suggest practical habits for using this Mac more efficiently.
        Recommend quitting or restarting specific apps only when the sample data supports it.
        Do not recommend disabling macOS system services.

        Format every reply in clean Markdown with this structure:

        ## Current memory state
        **Current:** <percent>%
        **Average:** <percent>%
        **Peak:** <percent>%
        **Trend:** <sample percentages joined by →>

        ## Persistent memory consumers
        - **<App name>:** avg <size>, peak <size> (<sample count> samples)

        ## Recommendations
        - **<Action title>:** <one sentence detail>

        ## Quitting or restarting apps
        - **<App name>:** <guidance; omit if not recommended>

        ## macOS system services
        - **<Service topic>:** <guidance — say when action is not recommended>

        ## Better computing habits
        Tip 1: <Short title> — <one sentence detail>
        Tip 2: <Short title> — <one sentence detail>
        Tip 3: <Short title> — <one sentence detail>

        Rules:
        - Put each section heading on its own line starting with ##
        - Put a blank line between sections
        - Put each bullet or tip on its own line
        - Never concatenate a heading with the next sentence
        - Never merge a tip title with its description
        - Use an em dash (—) between tip titles and descriptions
        """
    }
}
