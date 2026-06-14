import Foundation

public enum MemoryIssuePatternEngine {
    public static func analysisPrompt(for patterns: [MemoryIssuePatternSummary]) -> String {
        guard !patterns.isEmpty else {
            return "Summarize recurring memory issues and suggest better computing habits."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines = [
            "Analyze these recurring memory issues detected by DiskWise Memory Analyzer.",
            "Group similar problems, explain what the intervals mean, and recommend concrete user habits to reduce repeats.",
            "",
            "Recurring issues:",
        ]

        for pattern in patterns.prefix(12) {
            let avg = MemoryIssuePatternAnalyzer.formatInterval(pattern.averageInterval)
            let median = MemoryIssuePatternAnalyzer.formatInterval(pattern.medianInterval)
            lines.append(
                """
                - \(pattern.displayTitle): \(pattern.occurrenceCount) times, avg interval \(avg), median \(median), \
                typical memory \(String(format: "%.0f", pattern.typicalMemoryUsedPercent))%, \
                last seen \(formatter.string(from: pattern.lastSeenAt)), \
                alerts sent \(pattern.notificationCount), suppressed \(pattern.suppressedNotificationCount)
                """
            )
        }

        lines.append("")
        lines.append("Respond with: pattern summary, likely causes, and 3–5 habit changes to mitigate repeats.")
        return lines.joined(separator: "\n")
    }

    public static func ruleBasedAnalysis(for patterns: [MemoryIssuePatternSummary]) -> String {
        guard !patterns.isEmpty else {
            return "No recurring memory issues recorded yet. Keep Memory Analyzer enabled and DiskWise will build a history after a few alerts."
        }

        let top = patterns.prefix(5)
        var sections: [String] = [
            "**Recurring memory patterns**",
            "",
            "DiskWise grouped similar alerts so frequent repeats do not spam notifications. Review the table above for exact counts and intervals.",
            "",
        ]

        for pattern in top {
            let intervalText = intervalDescription(for: pattern)
            sections.append("**\(pattern.displayTitle)** — \(pattern.occurrenceCount) occurrences\(intervalText).")
            sections.append(mitigation(for: pattern))
            sections.append("")
        }

        sections.append("**General habits**")
        sections.append("")
        sections.append("• Close apps you are not using, especially browsers and creative tools.")
        sections.append("• Restart long-running apps weekly if the same issue keeps returning.")
        sections.append("• Trim login items and background helpers that relaunch after reboot.")
        sections.append("• Use Free Inactive Memory when usage stays high instead of waiting for pressure spikes.")

        return sections.joined(separator: "\n")
    }

    private static func intervalDescription(for pattern: MemoryIssuePatternSummary) -> String {
        guard let median = pattern.medianInterval else { return "" }
        let formatted = MemoryIssuePatternAnalyzer.formatInterval(median)
        if pattern.occurrenceCount >= 3, median < 3_600 {
            return ", often repeating every \(formatted)"
        }
        if pattern.occurrenceCount >= 2 {
            return ", typical gap \(formatted)"
        }
        return ""
    }

    private static func mitigation(for pattern: MemoryIssuePatternSummary) -> String {
        let target = pattern.targetProcessName.map { MemoryProcessRules.userFacingApplicationName(for: $0) } ?? ""

        switch pattern.actionKind {
        case .reduceTabs:
            return "→ Keep fewer tabs open in \(target.isEmpty ? "your browser" : target); bookmark sessions instead of leaving dozens of pages resident."
        case .quitProcess:
            return "→ Quit \(target.isEmpty ? "the app" : target) when finished, or disable reopen-windows-on-launch if it always restores a heavy session."
        case .restartApp:
            return "→ Restart \(target.isEmpty ? "the app" : target) after long sessions; if it repeats daily, check for updates or reduce extensions that leak memory."
        case .freeMemory:
            return "→ Sustained high memory use — close unused apps proactively and avoid running many heavy tools at once."
        case .informational:
            return "→ Review the suggested action when this pattern appears again."
        }
    }
}
