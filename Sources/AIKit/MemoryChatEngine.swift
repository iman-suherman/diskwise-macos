import Foundation

public enum MemoryChatEngine {
    public static func defaultQuestions(for report: MemoryAnalysisReport) -> [String] {
        var questions = [
            "What's using the most memory?",
            "Should I quit any apps?",
            "Why is memory pressure high?",
            "How do I free inactive memory?",
        ]
        if report.currentUsedPercent < 70 {
            questions.append("What habits will keep memory lower?")
        }
        return Array(questions.prefix(4))
    }

    public static func answer(question: String, context: MemoryAnalysisContext) -> String {
        let report = context.report
        let lower = question.lowercased()
        let bytes = ByteCountFormatter()
        bytes.countStyle = .memory

        if lower.contains("most") || lower.contains("using") || lower.contains("consumer") {
            if let top = report.persistentConsumers.first {
                let others = report.persistentConsumers.dropFirst().prefix(2)
                    .map { "**\($0.name)** — avg \(bytes.string(fromByteCount: $0.averageMemoryBytes))" }
                    .joined(separator: "\n")
                var answer = "**\(top.name)** is the heaviest persistent consumer, averaging \(bytes.string(fromByteCount: top.averageMemoryBytes)) across \(top.sampleCount) samples."
                if !others.isEmpty {
                    answer += "\n\nAlso notable:\n\(others)"
                }
                return answer
            }
            return "DiskWise is still collecting samples. Check back after a few minutes for persistent memory consumers."
        }

        if lower.contains("quit") || lower.contains("close") || lower.contains("restart") {
            let actionable = report.recommendations.filter {
                ($0.actionKind == .quitProcess || $0.actionKind == .restartApp)
                    && ($0.targetProcessName.map { !MemoryProcessRules.isDiskWise($0) } ?? true)
            }
            if actionable.isEmpty {
                return "No apps stand out as safe quit candidates right now. Memory use looks manageable based on recent samples."
            }
            let lines = actionable.prefix(4).map { "• **\($0.title)** — \($0.detail)" }.joined(separator: "\n")
            return "Based on your samples, consider these steps:\n\n\(lines)"
        }

        if lower.contains("pressure") || lower.contains("high") || lower.contains("why") {
            if report.currentUsedPercent >= 80 {
                return """
                Memory is under pressure at **\(String(format: "%.1f", report.currentUsedPercent))%** used (peak **\(String(format: "%.1f", report.peakUsedPercent))%**).

                macOS compresses and caches aggressively, but sustained high use slows the system. Free inactive memory, quit heavy background apps, and restart apps that have been open for days.
                """
            }
            return """
            Current use is **\(String(format: "%.1f", report.currentUsedPercent))%** with an average of **\(String(format: "%.1f", report.averageUsedPercent))%** across samples.

            That is within a normal range. Pressure spikes when many apps stay open or a few apps leak memory over time.
            """
        }

        if lower.contains("free") || lower.contains("inactive") || lower.contains("purge") {
            if report.currentUsedPercent >= 75 {
                return "Yes — freeing inactive memory is a good first step when use is above ~75%. Use **Free Inactive Memory** in the recommendations above. It clears compressed cache without quitting apps."
            }
            return "Inactive memory is mostly cache macOS can reclaim on demand. Purging is optional now; it helps most when usage stays above ~80%."
        }

        if lower.contains("habit") || lower.contains("lower") || lower.contains("efficient") {
            return """
            **Better computing habits**

            - **Close unused apps** — especially browsers and creative tools that stay resident in the background.
            - **Restart weekly** — long-lived apps can accumulate memory over days.
            - **Fewer browser tabs** — each tab adds RAM; use bookmarks instead of dozens of open pages.
            - **Check login items** — trim apps that launch at startup if you do not need them every session.
            """
        }

        let top = report.persistentConsumers.prefix(3)
            .map { "• **\($0.name)** — \(bytes.string(fromByteCount: $0.averageMemoryBytes)) avg" }
            .joined(separator: "\n")
        return """
        **Memory snapshot**

        - Current: **\(String(format: "%.1f", report.currentUsedPercent))%**
        - Average: **\(String(format: "%.1f", report.averageUsedPercent))%**
        - Peak: **\(String(format: "%.1f", report.peakUsedPercent))%**

        \(top.isEmpty ? "Still collecting consumer data." : "Top consumers:\n\(top)")

        Ask about quitting apps, freeing inactive memory, or what's using the most RAM.
        """
    }
}
