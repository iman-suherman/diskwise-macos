import Foundation
import MaintenanceKit

enum StartupAppsContextFormatter {
    static func format(_ context: StartupAppsAnalysisContext) -> String {
        let items = context.scanResult.items
        guard !items.isEmpty else {
            return "No startup apps were found on this Mac."
        }

        let lines = items.map { item -> String in
            var parts = [
                "Name: \(item.name)",
                "Source: \(item.source.displayName)",
            ]
            if let path = item.path {
                parts.append("Path: \(path)")
            }
            if let bundleID = item.bundleIdentifier {
                parts.append("Bundle ID: \(bundleID)")
            }
            if item.isHidden {
                parts.append("Hidden: yes")
            }
            if item.alsoInDock {
                parts.append("Also in Dock: yes")
            }
            if !item.detail.isEmpty {
                parts.append("Detail: \(item.detail)")
            }
            return parts.joined(separator: "\n")
        }

        return """
        Startup apps on this Mac (\(items.count) items):

        \(lines.joined(separator: "\n\n---\n\n"))
        """
    }

    static func analysisInstructions() -> String {
        """
        You are DiskWise, a privacy-first macOS performance consultant.
        Analyze each startup app and whether it should launch at computer boot.

        For every app listed, provide a section with this exact structure:

        ## <App Name>
        **Verdict:** Keep at login | Disable at login | Optional
        **Analysis:** One or two sentences explaining what the app does at startup and whether the user likely needs it every boot. Mention boot time, memory, and battery when relevant.

        Rules:
        - Analyze every app in the input list — do not skip any.
        - Use the exact app name from the input as the heading.
        - Keep at login: essential utilities the user likely needs every session (menu bar tools they rely on, sync clients they use daily, security tools).
        - Disable at login: games, updaters, infrequently used apps, duplicate chat clients, dev services not needed outside work hours.
        - Optional: useful sometimes but not essential every boot; user can open manually when needed.
        - Do not recommend disabling macOS system services or security software without strong reason.
        - Be practical and concise — no generic filler.
        - End with a brief ## Summary section (2–3 sentences) about overall startup load.
        """
    }
}

enum StartupAppsAnalysisParser {
    static func parse(_ text: String, items: [StartupAppItem]) -> [StartupAppAnalysis] {
        var analyses: [StartupAppAnalysis] = []
        let sections = splitSections(text)

        for item in items {
            let section = sections.first { heading, _ in
                normalized(heading) == normalized(item.name)
                    || normalized(item.name).contains(normalized(heading))
                    || normalized(heading).contains(normalized(item.name))
            }

            if let section {
                let recommendation = parseRecommendation(from: section.body)
                let analysis = parseAnalysisBody(from: section.body)
                analyses.append(
                    StartupAppAnalysis(
                        itemID: item.id,
                        recommendation: recommendation,
                        analysis: analysis
                    )
                )
            }
        }

        return analyses
    }

    static func parseSummary(_ text: String) -> String? {
        guard let summaryRange = text.range(of: "## Summary", options: .caseInsensitive) else { return nil }
        let summary = text[summaryRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private static func splitSections(_ text: String) -> [(heading: String, body: String)] {
        var sections: [(String, String)] = []
        var currentHeading: String?
        var currentBody: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if let heading = currentHeading {
                    sections.append((heading, currentBody.joined(separator: "\n")))
                }
                currentHeading = trimmed.replacingOccurrences(of: "## ", with: "")
                currentBody = []
            } else if currentHeading != nil {
                currentBody.append(String(line))
            }
        }

        if let heading = currentHeading {
            sections.append((heading, currentBody.joined(separator: "\n")))
        }

        return sections.filter { $0.0.caseInsensitiveCompare("Summary") != .orderedSame }
    }

    private static func parseRecommendation(from body: String) -> StartupAppRecommendation {
        let lower = body.lowercased()
        if lower.contains("**verdict:** disable") || lower.contains("verdict: disable") {
            return .disableAtLogin
        }
        if lower.contains("**verdict:** optional") || lower.contains("verdict: optional") {
            return .optional
        }
        return .keepAtLogin
    }

    private static func parseAnalysisBody(from body: String) -> String {
        if let range = body.range(of: "**Analysis:**", options: .caseInsensitive) {
            return body[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum RuleBasedStartupAppsEngine {
    static func analyze(items: [StartupAppItem]) -> [StartupAppAnalysis] {
        items.map { item in
            StartupAppAnalysis(
                itemID: item.id,
                recommendation: recommendation(for: item),
                analysis: analysis(for: item)
            )
        }
    }

    static func summary(for items: [StartupAppItem], analyses: [StartupAppAnalysis]) -> String {
        let disableCount = analyses.filter { $0.recommendation == .disableAtLogin }.count
        let optionalCount = analyses.filter { $0.recommendation == .optional }.count
        if items.isEmpty {
            return "No startup apps were detected."
        }
        if disableCount == 0 && optionalCount == 0 {
            return "Your \(items.count) startup items look reasonable. Review hidden login items if boot feels slow."
        }
        return "\(items.count) startup items found. Consider disabling \(disableCount) and reviewing \(optionalCount) optional items to speed up boot and reduce background memory use."
    }

    private static func recommendation(for item: StartupAppItem) -> StartupAppRecommendation {
        let name = item.name.lowercased()
        let bundle = item.bundleIdentifier?.lowercased() ?? ""
        let path = item.path?.lowercased() ?? ""

        if item.source == .launchAgent {
            if bundle.hasPrefix("homebrew.mxcl.") || path.contains("/homebrew/") {
                return .optional
            }
            if name.contains("update") || name.contains("helper") || name.contains("clean") {
                return .disableAtLogin
            }
            return .optional
        }

        if name.contains("steam") || name.contains("epic") || name.contains("battle.net") {
            return .disableAtLogin
        }

        if name.contains("dropbox") || name.contains("onedrive") || name.contains("google drive") {
            return .optional
        }

        if name.contains("slack") || name.contains("teams") || name.contains("discord") || name.contains("zoom") {
            return .optional
        }

        if name.contains("rectangle") || name.contains("bartender") || name.contains("amphetamine")
            || name.contains("alfred") || name.contains("raycast") || name.contains("itsycal") {
            return .keepAtLogin
        }

        if name.contains("mail") || name.contains("calendar") || name.contains("messages") {
            return .optional
        }

        if item.source == .dockPinned && !item.alsoLoginItem {
            return .optional
        }

        if item.isHidden {
            return .disableAtLogin
        }

        return .optional
    }

    private static func analysis(for item: StartupAppItem) -> String {
        switch item.source {
        case .loginItem:
            if item.alsoInDock {
                return "\(item.name) opens at login and stays in your Dock. Disable at login if you only need it occasionally — you can still launch it from the Dock."
            }
            return "\(item.name) is registered to open when you log in. Keep it only if you use it in every session."
        case .dockPinned:
            return "\(item.name) is pinned in the Dock but does not currently open at login. No change needed unless you enabled Open at Login separately."
        case .launchAgent:
            return "\(item.name) runs a background Launch Agent at login. Disable unless you rely on that service daily."
        case .backgroundItem:
            return "\(item.name) is registered as a background startup item. Review in System Settings → General → Login Items if you do not recognize it."
        }
    }
}
