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

    static var launchAtLoginStatusDescription: String {
        switch launchAtLoginService.status {
        case .enabled:
            return "DiskWise opens at login with the menu bar monitor"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .notRegistered:
            return "Menu bar monitor active while DiskWise is running"
        case .notFound:
            return "Install DiskWise from the release app to enable login at startup"
        @unknown default:
            return "Unknown status"
        }
    }

    @MainActor
    static func apply(enabled: Bool, settings: AppSettings) {
        if enabled {
            settings.showMenuBarDiskMonitor = true
            MenuBarStatusItemController.shared.setEnabled(true)
            unregisterLegacyLoginItemIfNeeded()

            do {
                try launchAtLoginService.register()
                openLoginItemsSettingsForApproval()
                if launchAtLoginService.status == .requiresApproval || !launchAtLoginEnabled {
                    settings.showMenuBarMonitorInstructions = true
                }
            } catch {
                settings.showMenuBarMonitorInstructions = true
            }
        } else {
            settings.showMenuBarDiskMonitor = false
            settings.showMenuBarMonitorInstructions = false
            MenuBarStatusItemController.shared.setEnabled(false)
            try? launchAtLoginService.unregister()
        }
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
