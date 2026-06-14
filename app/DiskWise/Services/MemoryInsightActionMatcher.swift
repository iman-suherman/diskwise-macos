import AIKit
import Foundation

enum MemoryInsightActionMatcher {
    static func recommendation(
        forTitle title: String?,
        body: String,
        report: MemoryAnalysisReport
    ) -> MemoryActionRecommendation? {
        let combined = [title, body].compactMap { $0 }.joined(separator: " ")
        if indicatesNoAction(combined) {
            return nil
        }

        if let title, let match = matchRecommendation(title: title, body: body, report: report) {
            return match.actionKind == .informational ? nil : match
        }

        if let title, let inferred = inferFromConsumer(title: title, body: body, report: report) {
            return inferred
        }

        return tipRecommendation(title: title ?? "", body: body, report: report)
    }

    private static func indicatesNoAction(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("not recommended")
            || lower.contains("do not ")
            || lower.contains("cannot ")
            || lower.contains("essential for system")
            || lower.contains("critical system service")
    }

    private static func matchRecommendation(
        title: String,
        body: String,
        report: MemoryAnalysisReport
    ) -> MemoryActionRecommendation? {
        let normalizedTitle = clean(title)
        return report.recommendations.first { recommendation in
            let target = recommendation.targetProcessName.map(clean) ?? ""
            let recTitle = clean(recommendation.title)
            return (!target.isEmpty && (normalizedTitle.localizedCaseInsensitiveContains(target)
                || target.localizedCaseInsensitiveContains(normalizedTitle)))
                || normalizedTitle.localizedCaseInsensitiveContains(recTitle)
                || recTitle.localizedCaseInsensitiveContains(normalizedTitle)
                || body.localizedCaseInsensitiveContains(target)
        }
    }

    private static func inferFromConsumer(
        title: String,
        body: String,
        report: MemoryAnalysisReport
    ) -> MemoryActionRecommendation? {
        let normalizedTitle = clean(title)
        guard let consumer = report.persistentConsumers.first(where: {
            normalizedTitle.localizedCaseInsensitiveContains($0.name)
                || $0.name.localizedCaseInsensitiveContains(normalizedTitle)
        }) else {
            return nil
        }

        let lower = body.lowercased()
        let name = consumer.name
        let avgGB = Double(consumer.averageMemoryBytes) / 1_073_741_824
        let nameLower = name.lowercased()

        if MemoryProcessRules.isDiskWise(name) {
            return nil
        }

        if nameLower.contains("chrome") || nameLower.contains("safari")
            || nameLower.contains("firefox") || nameLower.contains("edge") {
            return MemoryActionRecommendation(
                title: "Trim \(name) tabs",
                detail: body,
                actionKind: .reduceTabs,
                targetProcessName: name,
                priority: 70
            )
        }

        if lower.contains("quit") && !lower.contains("do not") {
            return MemoryActionRecommendation(
                title: "Quit \(name)",
                detail: body,
                actionKind: .quitProcess,
                targetProcessName: name,
                priority: 65
            )
        }

        if lower.contains("restart") || avgGB >= 1.5 {
            return MemoryActionRecommendation(
                title: "Restart \(name)",
                detail: body,
                actionKind: .restartApp,
                targetProcessName: name,
                priority: 75
            )
        }

        return nil
    }

    private static func tipRecommendation(
        title: String,
        body: String,
        report: MemoryAnalysisReport
    ) -> MemoryActionRecommendation? {
        let lower = (title + " " + body).lowercased()

        if lower.contains("free") && lower.contains("memory")
            || lower.contains("close") && lower.contains("app")
            || lower.contains("background app") {
            if report.currentUsedPercent >= 65 {
                return MemoryActionRecommendation(
                    title: title.isEmpty ? "Free inactive memory" : title,
                    detail: body,
                    actionKind: .freeMemory,
                    priority: 60
                )
            }
        }

        if lower.contains("tab") || lower.contains("browser") {
            if let browser = report.persistentConsumers.first(where: {
                let name = $0.name.lowercased()
                return name.contains("chrome") || name.contains("safari")
                    || name.contains("firefox") || name.contains("edge")
            }) {
                return MemoryActionRecommendation(
                    title: "Focus \(browser.name)",
                    detail: body,
                    actionKind: .reduceTabs,
                    targetProcessName: browser.name,
                    priority: 55
                )
            }
        }

        if lower.contains("restart") && !lower.contains("mac") {
            if let heavy = report.persistentConsumers.first(where: { !MemoryProcessRules.isDiskWise($0.name) }) {
                return MemoryActionRecommendation(
                    title: "Restart \(heavy.name)",
                    detail: body,
                    actionKind: .restartApp,
                    targetProcessName: heavy.name,
                    priority: 50
                )
            }
        }

        return nil
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }
}
