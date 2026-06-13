import AppKit
import DiskScannerKit
import Foundation

@MainActor
final class ScanLogMonitor: ObservableObject {
    static let shared = ScanLogMonitor()

    @Published private(set) var logLines: [String] = []
    @Published private(set) var logFileURL: URL?
    @Published private(set) var isActive = false

    private let maxLines = 200

    private init() {}

    func beginSession(_ session: PythonScanSession) {
        logLines = []
        logFileURL = session.logFileURL
        isActive = true
        append("Scanner log: \(session.logFileURL.path)")
        append("Python: \(session.pythonExecutable)")
    }

    func append(_ line: String) {
        guard !line.isEmpty else { return }
        logLines.append(line)
        if logLines.count > maxLines {
            logLines.removeFirst(logLines.count - maxLines)
        }
    }

    func endSession() {
        isActive = false
    }

    func reset() {
        logLines = []
        logFileURL = nil
        isActive = false
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
        var error: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
        if let error {
            append("Could not open Terminal: \(error)")
        }
    }

    func revealLogFile() {
        guard let logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
}
