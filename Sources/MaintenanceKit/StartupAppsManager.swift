import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

public enum StartupAppActionKind: String, Sendable, CaseIterable {
    case removeFromLogin
    case disableBackgroundActivity
    case unloadLaunchAgent
    case openLoginItemsSettings

    public var title: String {
        switch self {
        case .removeFromLogin: return "Remove from Login"
        case .disableBackgroundActivity: return "Disable in Settings"
        case .unloadLaunchAgent: return "Unload Agent"
        case .openLoginItemsSettings: return "Open Login Items"
        }
    }

    public var confirmationTitle: String {
        switch self {
        case .removeFromLogin: return "Remove from Open at Login?"
        case .disableBackgroundActivity: return "Disable background activity?"
        case .unloadLaunchAgent: return "Unload launch agent?"
        case .openLoginItemsSettings: return "Open Login Items Settings"
        }
    }

    public var isDestructive: Bool {
        switch self {
        case .removeFromLogin, .unloadLaunchAgent: return true
        case .disableBackgroundActivity, .openLoginItemsSettings: return false
        }
    }
}

public struct StartupAppActionResult: Sendable {
    public let action: StartupAppActionKind
    public let succeeded: Bool
    public let message: String

    public init(action: StartupAppActionKind, succeeded: Bool, message: String) {
        self.action = action
        self.succeeded = succeeded
        self.message = message
    }
}

public final class StartupAppsManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String
    private let osascriptPath: String
    private let launchctlPath: String

    public init(
        fileManager: FileManager = .default,
        homeDirectory: String? = nil,
        osascriptPath: String = "/usr/bin/osascript",
        launchctlPath: String = "/bin/launchctl"
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        self.osascriptPath = osascriptPath
        self.launchctlPath = launchctlPath
    }

    public func availableActions(
        for item: StartupAppItem,
        recommendation: StartupAppRecommendation?
    ) -> [StartupAppActionKind] {
        switch item.source {
        case .loginItem:
            guard item.isEnabled != false else { return [.openLoginItemsSettings] }
            guard recommendation != .keepAtLogin else { return [] }
            return [.removeFromLogin]
        case .backgroundItem:
            guard item.isEnabled == true else { return [] }
            guard recommendation == .disableAtLogin || recommendation == .optional else { return [] }
            return [.disableBackgroundActivity]
        case .launchAgent:
            guard recommendation == .disableAtLogin || recommendation == .optional else { return [] }
            return [.unloadLaunchAgent]
        case .dockPinned:
            if item.alsoLoginItem {
                return [.openLoginItemsSettings]
            }
            return []
        }
    }

    public func perform(_ action: StartupAppActionKind, on item: StartupAppItem) -> StartupAppActionResult {
        switch action {
        case .removeFromLogin:
            return removeFromLogin(item)
        case .disableBackgroundActivity:
            return disableBackgroundActivity(item)
        case .unloadLaunchAgent:
            return unloadLaunchAgent(item)
        case .openLoginItemsSettings:
            return StartupAppActionResult(
                action: action,
                succeeded: true,
                message: "Open System Settings → Login Items to change this startup item."
            )
        }
    }

    private func removeFromLogin(_ item: StartupAppItem) -> StartupAppActionResult {
        if let bundleID = item.bundleIdentifier, unregisterLoginService(bundleIdentifier: bundleID) {
            return StartupAppActionResult(
                action: .removeFromLogin,
                succeeded: true,
                message: "Removed \(item.name) from Open at Login."
            )
        }

        if removeLoginItemViaAppleScript(name: item.name) {
            return StartupAppActionResult(
                action: .removeFromLogin,
                succeeded: true,
                message: "Removed \(item.name) from Open at Login."
            )
        }

        if let path = item.path {
            let displayName = fileManager.displayName(atPath: path)
            if displayName != item.name && removeLoginItemViaAppleScript(name: displayName) {
                return StartupAppActionResult(
                    action: .removeFromLogin,
                    succeeded: true,
                    message: "Removed \(item.name) from Open at Login."
                )
            }
        }

        return StartupAppActionResult(
            action: .removeFromLogin,
            succeeded: false,
            message: "Could not remove \(item.name). Open Login Items in System Settings and turn it off manually."
        )
    }

    private func disableBackgroundActivity(_ item: StartupAppItem) -> StartupAppActionResult {
        StartupAppActionResult(
            action: .disableBackgroundActivity,
            succeeded: true,
            message: "In System Settings, find \(item.name) under App Background Activity and turn it off."
        )
    }

    private func unloadLaunchAgent(_ item: StartupAppItem) -> StartupAppActionResult {
        let label = item.bundleIdentifier ?? item.name
        let plistPath = (homeDirectory as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")

        guard fileManager.fileExists(atPath: plistPath) else {
            return StartupAppActionResult(
                action: .unloadLaunchAgent,
                succeeded: false,
                message: "Launch agent plist not found at \(plistPath)."
            )
        }

        let uid = getuid()
        let bootout = runCommand(
            path: launchctlPath,
            arguments: ["bootout", "gui/\(uid)", plistPath]
        )
        if bootout.terminationStatus != 0 {
            _ = runCommand(
                path: launchctlPath,
                arguments: ["unload", plistPath]
            )
        }

        do {
            try fileManager.removeItem(atPath: plistPath)
            return StartupAppActionResult(
                action: .unloadLaunchAgent,
                succeeded: true,
                message: "Unloaded and removed \(label)."
            )
        } catch {
            return StartupAppActionResult(
                action: .unloadLaunchAgent,
                succeeded: false,
                message: "Stopped \(label), but could not delete the plist: \(error.localizedDescription)"
            )
        }
    }

    private func removeLoginItemViaAppleScript(name: String) -> Bool {
        let escaped = escapeAppleScriptString(name)
        let script = """
        tell application "System Events"
            repeat with li in login items
                if name of li is "\(escaped)" then
                    delete li
                    return "ok"
                end if
            end repeat
            return "missing"
        end tell
        """
        let result = runCommand(path: osascriptPath, arguments: ["-e", script])
        return result.terminationStatus == 0 && result.output == "ok"
    }

    private func unregisterLoginService(bundleIdentifier: String) -> Bool {
        #if canImport(ServiceManagement)
        let service = SMAppService.loginItem(identifier: bundleIdentifier)
        guard service.status != .notFound else { return false }
        do {
            try service.unregister()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private struct CommandResult {
        let output: String?
        let terminationStatus: Int32
    }

    private func runCommand(path: String, arguments: [String], timeout: TimeInterval = 15) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let group = DispatchGroup()
        group.enter()
        var terminationStatus: Int32 = -1

        process.terminationHandler = { process in
            terminationStatus = process.terminationStatus
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return CommandResult(output: nil, terminationStatus: -1)
        }

        let completed = group.wait(timeout: .now() + timeout) == .success
        if !completed {
            process.terminate()
            return CommandResult(output: nil, terminationStatus: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(output: output, terminationStatus: terminationStatus)
    }
}
