import Foundation

public final class SystemOptimizer: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String

    public init(fileManager: FileManager = .default, homeDirectory: String? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
    }

    public func availableTasks() -> [OptimizationTask] {
        [
            OptimizationTask(
                id: "refresh_finder",
                title: "Refresh Finder",
                detail: "Restarts Finder to clear stale folder views and refresh icons.",
                requiresConfirmation: true,
                isDestructive: false
            ),
            OptimizationTask(
                id: "refresh_dock",
                title: "Refresh Dock",
                detail: "Restarts the Dock to apply layout and icon changes.",
                requiresConfirmation: true,
                isDestructive: false
            ),
            OptimizationTask(
                id: "clear_diagnostic_logs",
                title: "Clear Diagnostic Logs",
                detail: "Removes user diagnostic and crash reports from ~/Library/Logs.",
                requiresConfirmation: true,
                isDestructive: true
            ),
            OptimizationTask(
                id: "rebuild_launch_services",
                title: "Rebuild Launch Services",
                detail: "Refreshes the database macOS uses to open files with apps.",
                requiresConfirmation: true,
                isDestructive: false
            ),
            OptimizationTask(
                id: "clear_dns_cache",
                title: "Flush DNS Cache",
                detail: "Runs dscacheutil to flush the local DNS cache. May require admin privileges.",
                requiresConfirmation: true,
                isDestructive: false
            ),
        ]
    }

    public func run(taskID: String) -> OptimizationResult {
        switch taskID {
        case "refresh_finder":
            return runShellCommand("/usr/bin/killall", arguments: ["Finder"], successMessage: "Finder refreshed.")
        case "refresh_dock":
            return runShellCommand("/usr/bin/killall", arguments: ["Dock"], successMessage: "Dock refreshed.")
        case "clear_diagnostic_logs":
            return clearDiagnosticLogs()
        case "rebuild_launch_services":
            return rebuildLaunchServices()
        case "clear_dns_cache":
            return flushDNSCache()
        default:
            return OptimizationResult(taskID: taskID, succeeded: false, message: "Unknown optimization task.")
        }
    }

    private func clearDiagnosticLogs() -> OptimizationResult {
        let folders = [
            (homeDirectory as NSString).appendingPathComponent("Library/Logs/DiagnosticReports"),
            (homeDirectory as NSString).appendingPathComponent("Library/Logs/CrashReporter"),
        ]

        var removed = 0
        for folder in folders {
            guard fileManager.fileExists(atPath: folder) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: folder) else { continue }
            for name in contents {
                let path = (folder as NSString).appendingPathComponent(name)
                try? fileManager.removeItem(atPath: path)
                removed += 1
            }
        }

        return OptimizationResult(
            taskID: "clear_diagnostic_logs",
            succeeded: true,
            message: removed > 0 ? "Removed \(removed) diagnostic files." : "No diagnostic files found."
        )
    }

    private func rebuildLaunchServices() -> OptimizationResult {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard fileManager.fileExists(atPath: lsregister) else {
            return OptimizationResult(taskID: "rebuild_launch_services", succeeded: false, message: "Launch Services tool not found.")
        }
        return runShellCommand(lsregister, arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"], successMessage: "Launch Services database rebuilt.")
    }

    private func flushDNSCache() -> OptimizationResult {
        let result = runShellCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"], successMessage: "DNS cache flushed.")
        if result.succeeded {
            _ = runShellCommand("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], successMessage: "")
        }
        return result
    }

    @discardableResult
    private func runShellCommand(_ launchPath: String, arguments: [String], successMessage: String) -> OptimizationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            let succeeded = process.terminationStatus == 0
            return OptimizationResult(
                taskID: arguments.first ?? launchPath,
                succeeded: succeeded,
                message: succeeded ? successMessage : "Command failed with status \(process.terminationStatus)."
            )
        } catch {
            return OptimizationResult(
                taskID: arguments.first ?? launchPath,
                succeeded: false,
                message: error.localizedDescription
            )
        }
    }
}
