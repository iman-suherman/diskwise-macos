import AppKit
import AIKit

@MainActor
enum MemoryActionExecutor {
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
            return activateApplication(named: name) ?? "No action required."
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

    private static var manageableApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            switch app.activationPolicy {
            case .regular, .accessory:
                return true
            default:
                return false
            }
        }
    }

    private static func isInstalledAppBundle(_ app: NSRunningApplication) -> Bool {
        app.bundleURL?.pathExtension == "app"
    }

    private static func runningApplication(named name: String) -> NSRunningApplication? {
        let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
        let searchNames = uniqueNames(resolvedName, name)

        for searchName in searchNames {
            if let app = manageableApplications.first(where: { app in
                isInstalledAppBundle(app)
                    && app.localizedName?.caseInsensitiveCompare(searchName) == .orderedSame
            }) {
                return app
            }
        }

        let processNameLower = name.lowercased()
        if let app = manageableApplications.first(where: { app in
            guard isInstalledAppBundle(app), let localized = app.localizedName else { return false }
            return processNameLower.hasPrefix(localized.lowercased() + " ")
        }) {
            return app
        }

        if let bundleFragment = MemoryProcessRules.knownBundleFragment(forApplicationName: name),
           let app = manageableApplications.first(where: {
               $0.bundleIdentifier?.localizedCaseInsensitiveContains(bundleFragment) == true
                   && isInstalledAppBundle($0)
           }) {
            return app
        }

        return manageableApplications.first { app in
            guard isInstalledAppBundle(app), let localized = app.localizedName else { return false }
            let localizedLower = localized.lowercased()
            let resolvedLower = resolvedName.lowercased()
            return localizedLower == resolvedLower
                || localizedLower.contains(resolvedLower)
                || resolvedLower.contains(localizedLower)
        }
    }

    private static func installedApplicationBundleURL(for name: String) -> URL? {
        guard let bundleFragment = MemoryProcessRules.knownBundleFragment(forApplicationName: name) else {
            return nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleFragment)
    }

    private static func runningApplications(withBundleURL bundleURL: URL) -> [NSRunningApplication] {
        manageableApplications.filter { $0.bundleURL == bundleURL }
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

    private static func displayName(for app: NSRunningApplication?, fallback: String) -> String {
        app?.localizedName ?? MemoryProcessRules.userFacingApplicationName(for: fallback)
    }

    private static func quitApplication(named name: String) -> String {
        let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
        if let app = runningApplication(named: name) {
            let appName = displayName(for: app, fallback: name)
            return app.terminate()
                ? "Sent quit signal to \(appName)."
                : "Could not quit \(appName). It may ignore quit requests."
        }

        if let bundleURL = installedApplicationBundleURL(for: name) {
            let running = runningApplications(withBundleURL: bundleURL)
            guard !running.isEmpty else {
                return "\(resolvedName) is not running."
            }
            var terminatedAny = false
            for app in running {
                terminatedAny = app.terminate() || terminatedAny
            }
            return terminatedAny
                ? "Sent quit signal to \(resolvedName)."
                : "Could not quit \(resolvedName). It may ignore quit requests."
        }

        return "\(resolvedName) is not running as a user application."
    }

    private static func restartApplication(named name: String) -> String {
        let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
        let bundleURL = runningApplication(named: name)?.bundleURL ?? installedApplicationBundleURL(for: name)
        guard let bundleURL else {
            return "\(resolvedName) is not running as a user application."
        }

        let appName = displayName(for: runningApplication(named: name), fallback: name)
        for app in runningApplications(withBundleURL: bundleURL) {
            app.terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
        }
        return "Restarting \(appName)…"
    }

    static func canFocusApplication(named name: String) -> Bool {
        runningApplication(named: name) != nil
    }

    static func focusAppAlertTitle(for processName: String) -> String {
        let appName = MemoryProcessRules.userFacingApplicationName(for: processName)
        return "Free memory in \(appName)"
    }

    static func focusAppInstructions(for processName: String) -> String {
        let appName = MemoryProcessRules.userFacingApplicationName(for: processName)
        let lower = appName.lowercased()

        if lower.contains("chrome") || lower.contains("chromium") {
            return """
            Chrome keeps every tab in memory. To reclaim RAM:

            • Close tabs you are not using
            • Bookmark pages and close the tab instead of leaving it open
            • Open Window → Task Manager to find tabs using the most memory

            When you are ready, open Chrome and trim tabs there.
            """
        }
        if lower.contains("safari") {
            return """
            Safari can use a lot of memory with many tabs open. To free RAM:

            • Close tabs you no longer need
            • Use Window → Tab Overview to spot duplicate or heavy pages
            • Turn on tab limits in Safari Settings if you keep many tabs open

            When you are ready, open Safari and close unused tabs.
            """
        }
        if lower.contains("firefox") {
            return """
            Firefox runs each tab as its own process. To free RAM:

            • Close tabs you are not using
            • Open about:performance or Task Manager to find heavy tabs
            • Suspend or remove extensions you do not need

            When you are ready, open Firefox and trim tabs there.
            """
        }
        if lower.contains("edge") {
            return """
            Edge keeps tabs and extensions in memory. To free RAM:

            • Close tabs you are not using
            • Open Browser Task Manager (⋯ → More tools) to find heavy tabs
            • Disable extensions you do not need

            When you are ready, open Edge and close unused tabs.
            """
        }

        return """
        \(appName) is using significant memory. Close unused windows, tabs, or documents in the app to reclaim RAM.

        When you are ready, open \(appName) to clean up there.
        """
    }

    static func focusAppCTATitle(for processName: String) -> String {
        "Open \(MemoryProcessRules.userFacingApplicationName(for: processName))"
    }

    @discardableResult
    static func focusApplication(named name: String) -> String? {
        activateApplication(named: name)
    }

    @discardableResult
    private static func activateApplication(named name: String) -> String? {
        guard let app = runningApplication(named: name) else {
            let resolvedName = MemoryProcessRules.userFacingApplicationName(for: name)
            return "\(resolvedName) is not running."
        }
        app.activate()
        return nil
    }
}
