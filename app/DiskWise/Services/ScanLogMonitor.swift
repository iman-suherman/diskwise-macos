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

        if openTailViaCommandFile(logFileURL: logFileURL) {
            return
        }

        openTailViaAppleScript(logFileURL: logFileURL)
    }

    func revealLogFile() {
        guard let logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func openTailViaCommandFile(logFileURL: URL) -> Bool {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-scan-log-\(ProcessInfo.processInfo.processIdentifier).command")

        let quotedPath = logFileURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let contents = """
        #!/bin/bash
        clear
        echo "DiskWise scan log — following verbose output"
        echo "Log file: \(logFileURL.path)"
        echo ""
        tail -f '\(quotedPath)'
        """

        do {
            try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
            return true
        } catch {
            return false
        }
    }

    private func openTailViaAppleScript(logFileURL: URL) {
        let escapedPath = logFileURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Terminal"
            launch
            activate
            delay 0.15
            do script "tail -f " & quoted form of "\(escapedPath)"
        end tell
        tell application "System Events"
            set frontmost of the first process whose name is "Terminal" to true
        end tell
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&errorInfo)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
