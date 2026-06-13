import AppKit
import DiskScannerKit
import Foundation

@MainActor
final class ScanLogMonitor: ObservableObject {
    static let shared = ScanLogMonitor()

    @Published private(set) var logFileURL: URL?
    @Published private(set) var isActive = false

    var tailCommand: String? {
        guard let logFileURL else { return nil }
        return "tail -f \(shellQuoted(logFileURL.path))"
    }

    private init() {}

    func beginSession(_ session: PythonScanSession) {
        logFileURL = session.logFileURL
        isActive = true
    }

    func endSession() {
        isActive = false
    }

    func reset() {
        logFileURL = nil
        isActive = false
    }

    func copyLogPath() {
        guard let logFileURL else { return }
        copyToClipboard(logFileURL.path)
    }

    func copyTailCommand() {
        guard let tailCommand else { return }
        copyToClipboard(tailCommand)
    }

    func openInTerminal() {
        guard let logFileURL else { return }

        let escapedPath = logFileURL.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "echo 'DiskWise scan log — verbose output'; echo 'Log file: \(escapedPath)'; echo ''; tail -f '\(escapedPath)'"
        end tell
        """
        NSAppleScript(source: scriptSource)?.executeAndReturnError(nil)
    }

    func revealLogFile() {
        guard let logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
