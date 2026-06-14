import AppKit
import AIKit

@MainActor
enum MemoryActionExecutor {
    private struct BrowserBundleHint {
        let keyword: String
        let bundleFragment: String
    }

    private static let browserBundleHints: [BrowserBundleHint] = [
        BrowserBundleHint(keyword: "chrome", bundleFragment: "google.Chrome"),
        BrowserBundleHint(keyword: "firefox", bundleFragment: "org.mozilla.firefox"),
        BrowserBundleHint(keyword: "safari", bundleFragment: "com.apple.Safari"),
        BrowserBundleHint(keyword: "edge", bundleFragment: "com.microsoft.edgemac"),
    ]

    static func perform(_ recommendation: MemoryActionRecommendation) async -> String {
        await perform(
            kind: recommendation.actionKind,
            targetProcessName: recommendation.targetProcessName
        )
    }

    static func perform(kind: MemoryActionKind, targetProcessName: String?) async -> String {
        switch kind {
        case .freeMemory:
            let result = await SystemHealthMonitor.shared.freeUpMemory()
            return resultMessage(for: result)
        case .quitProcess:
            guard let name = targetProcessName else {
                return "No app specified for this action."
            }
            return quitApplication(named: name)
        case .restartApp:
            guard let name = targetProcessName else {
                return "No app specified for this action."
            }
            return restartApplication(named: name)
        case .reduceTabs:
            guard let name = targetProcessName else {
                return "No app specified for this action."
            }
            return activateApplication(named: name)
        case .informational:
            return "No action required."
        }
    }

    static func actionTitle(for recommendation: MemoryActionRecommendation) -> String? {
        switch recommendation.actionKind {
        case .freeMemory: return "Free Memory"
        case .quitProcess: return "Quit"
        case .restartApp: return "Restart"
        case .reduceTabs: return "Focus App"
        case .informational: return nil
        }
    }

    static func resultMessage(for result: MemoryReliefResult) -> String {
        switch result {
        case .relieved(_, let message): return message
        case .improved(let message): return message
        case .noMeasurableChange(let message): return message
        case .requiresAdmin(let message): return message
        case .failed(let message): return message
        }
    }

    private static var userFacingApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private static func runningApplication(named name: String) -> NSRunningApplication? {
        let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
        let searchNames = uniqueNames(resolvedName, name)

        for searchName in searchNames {
            if let app = userFacingApplications.first(where: { app in
                app.localizedName?.caseInsensitiveCompare(searchName) == .orderedSame
            }) {
                return app
            }
        }

        let processNameLower = name.lowercased()
        if let app = userFacingApplications.first(where: { app in
            guard let localized = app.localizedName else { return false }
            return processNameLower.hasPrefix(localized.lowercased() + " ")
        }) {
            return app
        }

        let resolvedLower = resolvedName.lowercased()
        for hint in browserBundleHints where resolvedLower.contains(hint.keyword) {
            if let app = userFacingApplications.first(where: {
                $0.bundleIdentifier?.localizedCaseInsensitiveContains(hint.bundleFragment) == true
            }) {
                return app
            }
        }

        return userFacingApplications.first { app in
            guard let localized = app.localizedName else { return false }
            let localizedLower = localized.lowercased()
            return localizedLower.contains(resolvedLower) || resolvedLower.contains(localizedLower)
        }
    }

    private static func uniqueNames(_ names: String...) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func displayName(for app: NSRunningApplication, fallback: String) -> String {
        app.localizedName ?? MemoryProcessRules.userFacingApplicationName(for: fallback)
    }

    private static func quitApplication(named name: String) -> String {
        guard let app = runningApplication(named: name) else {
            let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
            return "\(resolvedName) is not running as a user application."
        }
        let appName = displayName(for: app, fallback: name)
        return app.terminate()
            ? "Sent quit signal to \(appName)."
            : "Could not quit \(appName). It may ignore quit requests."
    }

    private static func restartApplication(named name: String) -> String {
        guard let app = runningApplication(named: name),
              let bundleURL = app.bundleURL else {
            let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
            return "\(resolvedName) is not running as a user application."
        }
        let appName = displayName(for: app, fallback: name)
        _ = app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
        }
        return "Restarting \(appName)…"
    }

    private static func activateApplication(named name: String) -> String {
        guard let app = runningApplication(named: name) else {
            let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
            return "\(resolvedName) is not running."
        }
        app.activate()
        let appName = displayName(for: app, fallback: name)
        return "Brought \(appName) to the front so you can close unused tabs."
    }
}
