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
        alert.messageText = "Show disk space in the menu bar?"
        alert.informativeText = """
        DiskWise can show Macintosh HD usage in the menu bar with a percentage and bar chart. \
        The monitor runs inside DiskWise and can start automatically when you log in. macOS will open System Settings so you can approve DiskWise under Login Items.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .install : .dismiss
    }

    @MainActor
    static func presentApprovalPrompt() -> Response {
        let alert = NSAlert()
        alert.messageText = "Approve DiskWise at login"
        alert.informativeText = """
        Turn on DiskWise under Open at Login in System Settings so the menu bar disk monitor starts when you log in.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .openSettings : .dismiss
    }
}
