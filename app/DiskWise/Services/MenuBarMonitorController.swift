import AppKit
import Foundation
import ServiceManagement

enum MenuBarMonitorController {
    static let legacyLoginItemBundleID = "net.suherman.diskwise.menubar"

    static var launchAtLoginService: SMAppService {
        SMAppService.mainApp
    }

    static var launchAtLoginEnabled: Bool {
        launchAtLoginService.status == .enabled
    }

    static var menuBarMonitorStatusDescription: String {
        "Shows remaining disk space with a color-coded bar while DiskWise is running."
    }

    static var launchAtLoginStatusDescription: String {
        switch launchAtLoginService.status {
        case .enabled:
            return "DiskWise opens automatically when you log in"
        case .requiresApproval:
            return "Approve DiskWise in System Settings → Login Items"
        case .notRegistered:
            return "DiskWise opens only when you launch it manually"
        case .notFound:
            return "Install DiskWise from the release app to enable login at startup"
        @unknown default:
            return "Unknown status"
        }
    }

    @MainActor
    static func applyMenuBarMonitor(enabled: Bool, settings: AppSettings) {
        settings.showMenuBarDiskMonitor = enabled
        settings.showMenuBarMonitorInstructions = false
        MenuBarStatusItemController.shared.setEnabled(enabled)
        unregisterLegacyLoginItemIfNeeded()
    }

    @MainActor
    static func applyLaunchAtLogin(enabled: Bool, settings: AppSettings) {
        if enabled {
            do {
                try launchAtLoginService.register()
                if launchAtLoginService.status == .requiresApproval {
                    openLoginItemsSettingsForApproval()
                }
            } catch {
                settings.launchAtLogin = false
                return
            }
        } else {
            try? launchAtLoginService.unregister()
        }

        settings.launchAtLogin = enabled
    }

    static func unregisterLegacyLoginItemIfNeeded() {
        let legacy = SMAppService.loginItem(identifier: legacyLoginItemBundleID)
        guard legacy.status != .notFound else { return }
        try? legacy.unregister()
    }

    static func openLoginItemsSettingsForApproval() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?UserItems",
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
}
