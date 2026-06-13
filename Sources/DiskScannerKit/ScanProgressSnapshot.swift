import Foundation

/// Thread-safe progress snapshot written by the scanner and read periodically by the UI.
public final class ScanProgressSnapshot: @unchecked Sendable {
    public static let shared = ScanProgressSnapshot()

    private let lock = NSLock()
    private var latest: ScanProgress?
    private var statusFileURL: URL?

    private init() {}

    public func bindStatusFile(_ url: URL) {
        lock.lock()
        statusFileURL = url
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        latest = nil
        statusFileURL = nil
        lock.unlock()
    }

    public func update(_ progress: ScanProgress) {
        lock.lock()
        latest = progress
        let fileURL = statusFileURL
        lock.unlock()

        if let fileURL {
            Self.writeProgress(progress, to: fileURL)
        }
    }

    public func currentProgress() -> ScanProgress? {
        lock.lock()
        defer { lock.unlock() }

        if let latest {
            return latest
        }
        guard let fileURL = statusFileURL else { return nil }
        return Self.readProgress(from: fileURL)
    }

    public static func makeStatusFileURL(near logFileURL: URL) -> URL {
        logFileURL.deletingPathExtension().appendingPathExtension("progress.json")
    }

    private static func writeProgress(_ progress: ScanProgress, to url: URL) {
        var payload: [String: Any] = [
            "scannedCount": progress.scannedCount,
            "currentPath": progress.currentPath,
            "bytesIndexed": progress.bytesIndexed,
            "operation": progress.operation.rawValue,
            "updatedAt": Date().timeIntervalSince1970,
        ]
        if let detail = progress.detail { payload["detail"] = detail }
        if let processed = progress.directoriesProcessed { payload["directoriesProcessed"] = processed }
        if let total = progress.directoriesTotal { payload["directoriesTotal"] = total }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func readProgress(from url: URL) -> ScanProgress? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let operationRaw = json["operation"] as? String ?? ScanOperation.enumeratingFiles.rawValue
        let operation = ScanOperation(rawValue: operationRaw) ?? .enumeratingFiles
        return ScanProgress(
            scannedCount: json["scannedCount"] as? Int ?? 0,
            currentPath: json["currentPath"] as? String ?? "",
            bytesIndexed: json["bytesIndexed"] as? Int64 ?? Int64(json["bytesIndexed"] as? Int ?? 0),
            operation: operation,
            detail: json["detail"] as? String,
            directoriesProcessed: json["directoriesProcessed"] as? Int,
            directoriesTotal: json["directoriesTotal"] as? Int
        )
    }
}

/// Reads the last meaningful line from a scanner log file for display.
public enum ScanLogTailReader {
    public static func lastStatusLine(from logFileURL: URL, maxBytes: Int = 16_384) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64) ?? 0
        if fileSize <= 0 { return nil }

        let readOffset = max(0, fileSize - Int64(maxBytes))
        try? handle.seek(toOffset: UInt64(readOffset))
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.last
    }
}
