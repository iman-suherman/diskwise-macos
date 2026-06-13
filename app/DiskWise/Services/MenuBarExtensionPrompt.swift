import AppKit

enum MenuBarExtensionPrompt {
    enum Response {
        case install
        case openSettings
        case dismiss
    }

    @MainActor
    static func presentInstallPrompt() -> Response {
        let alert = NSAlert()
        alert.messageText = "Install menu bar disk monitor?"
        alert.informativeText = """
        DiskWise can show Macintosh HD usage in the menu bar with a percentage and bar chart. \
        It starts automatically when you log in. macOS will open System Settings so you can approve the login item.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .install : .dismiss
    }

    @MainActor
    static func presentApprovalPrompt() -> Response {
        let alert = NSAlert()
        alert.messageText = "Approve menu bar monitor"
        alert.informativeText = """
        Turn on “DiskWise Menu Bar” under Login Items in System Settings to show Macintosh HD usage in the menu bar at login.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .openSettings : .dismiss
    }
}
