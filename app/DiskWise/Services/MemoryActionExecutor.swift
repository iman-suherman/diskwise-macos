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

    private static func runningApplication(named name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
                || ($0.localizedName?.lowercased().contains(name.lowercased()) == true)
        }
    }

    private static func quitApplication(named name: String) -> String {
        guard let app = runningApplication(named: name) else {
            return "\(name) is not running as a user application."
        }
        return app.terminate()
            ? "Sent quit signal to \(name)."
            : "Could not quit \(name). It may ignore quit requests."
    }

    private static func restartApplication(named name: String) -> String {
        guard let app = runningApplication(named: name),
              let bundleURL = app.bundleURL else {
            return "\(name) is not running as a user application."
        }
        let localizedName = app.localizedName ?? name
        _ = app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
        }
        return "Restarting \(localizedName)…"
    }

    private static func activateApplication(named name: String) -> String {
        guard let app = runningApplication(named: name) else {
            return "\(name) is not running."
        }
        app.activate()
        return "Brought \(name) to the front so you can close unused tabs."
    }
}
