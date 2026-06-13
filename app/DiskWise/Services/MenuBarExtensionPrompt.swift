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
        DiskWise can show remaining Macintosh HD space in the menu bar as a color-coded percentage. \
        The monitor runs while DiskWise is open — it does not require login at startup.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Not Now")

        return alert.runModal() == .alertFirstButtonReturn ? .install : .dismiss
    }
}
