import AppKit
import Foundation
import ServiceManagement

enum MenuBarExtensionInstaller {
    static let loginItemBundleID = "net.suherman.diskwise.menubar"
    static let helperAppName = "DiskWiseMenuBar.app"

    static var embeddedHelperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/\(helperAppName)")
    }

    static var isHelperBundled: Bool {
        FileManager.default.fileExists(atPath: embeddedHelperURL.path)
    }

    static var service: SMAppService {
        SMAppService.loginItem(identifier: loginItemBundleID)
    }

    static var isInstalled: Bool {
        service.status == .enabled
    }

    static var statusDescription: String {
        switch service.status {
        case .enabled:
            return "Running at login"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .notRegistered:
            return "Not installed"
        case .notFound:
            return "Helper not found in app bundle"
        @unknown default:
            return "Unknown status"
        }
    }

    @discardableResult
    static func install() throws -> Bool {
        guard isHelperBundled else {
            throw InstallError.helperMissing
        }

        try service.register()
        openLoginItemsSettingsForApproval()

        if isInstalled {
            launchHelperNow()
        }

        return isInstalled
    }

    static func uninstall() throws {
        try service.unregister()
    }

    static func launchHelperNow() {
        guard isHelperBundled else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: embeddedHelperURL, configuration: configuration)
    }

    static func openLoginItemsSettingsForApproval() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems",
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.LoginItems",
        ]

        for link in urls {
            if let url = URL(string: link), NSWorkspace.shared.open(url) {
                return
            }
        }

        SMAppService.openSystemSettingsLoginItems()
    }

    enum InstallError: LocalizedError {
        case helperMissing

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "The menu bar monitor could not be found inside the DiskWise app bundle."
            }
        }
    }
}
