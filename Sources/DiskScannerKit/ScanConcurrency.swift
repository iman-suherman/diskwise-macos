import Foundation

public enum ScanConcurrency {
    public static var maxParallelTasks: Int { 1 }

    public static func displayLabel(for path: String, relativeTo root: String? = nil) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let root {
            let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
            if standardized == rootPath {
                return URL(fileURLWithPath: rootPath).lastPathComponent
            }
            let prefix = rootPath + "/"
            if standardized.hasPrefix(prefix) {
                return String(standardized.dropFirst(prefix.count))
            }
        }
        return URL(fileURLWithPath: standardized).path
            .split(separator: "/")
            .suffix(3)
            .joined(separator: "/")
    }
}

final class ScanProgressAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var scannedCount: Int
    private var indexedBytes: Int64
    private let identifiedDirectories: [String]
    private let directoriesTotal: Int
    private let maxConcurrency: Int
    private let scanRootPath: String
    private let onProgress: (@Sendable (ScanProgress) -> Void)?
    private var activePaths: [String] = []
    private var completedLabels: [String] = []
    private var completedCount = 0

    var scanRootPathForDisplay: String { scanRootPath }

    init(
        scannedCount: Int,
        indexedBytes: Int64,
        identifiedDirectories: [String],
        directoriesTotal: Int,
        maxConcurrency: Int = ScanConcurrency.maxParallelTasks,
        scanRootPath: String,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) {
        self.scannedCount = scannedCount
        self.indexedBytes = indexedBytes
        self.identifiedDirectories = identifiedDirectories
        self.directoriesTotal = directoriesTotal
        self.maxConcurrency = maxConcurrency
        self.scanRootPath = scanRootPath
        self.onProgress = onProgress
    }

    func willBegin(_ path: String, operation: ScanOperation, detail: String) {
        lock.lock()
        if !activePaths.contains(path) {
            activePaths.append(path)
        }
        let snapshot = snapshot(currentPath: path, operation: operation, detail: detail)
        lock.unlock()
        onProgress?(snapshot)
    }

    func didComplete(_ path: String, results: [ScannedFile], operation: ScanOperation, detail: String) {
        lock.lock()
        activePaths.removeAll { $0 == path }
        completedCount += 1
        completedLabels.append(ScanConcurrency.displayLabel(for: path, relativeTo: scanRootPath))
        scannedCount += results.filter { !$0.isDirectory }.count
        indexedBytes += results.reduce(Int64(0)) { partial, entry in
            partial + (entry.isDirectory ? 0 : entry.size)
        }
        let snapshot = snapshot(currentPath: path, operation: operation, detail: detail)
        lock.unlock()
        onProgress?(snapshot)
    }

    func emit(currentPath: String, operation: ScanOperation, detail: String) {
        lock.lock()
        let snapshot = snapshot(currentPath: currentPath, operation: operation, detail: detail)
        lock.unlock()
        onProgress?(snapshot)
    }

    private func snapshot(currentPath: String, operation: ScanOperation, detail: String) -> ScanProgress {
        ScanProgress(
            scannedCount: scannedCount,
            currentPath: currentPath,
            bytesIndexed: indexedBytes,
            operation: operation,
            detail: detail,
            directoriesProcessed: completedCount,
            directoriesTotal: directoriesTotal,
            maxConcurrency: maxConcurrency,
            activeConcurrency: activePaths.count,
            identifiedDirectories: identifiedDirectories,
            activeDirectories: activePaths.map { ScanConcurrency.displayLabel(for: $0, relativeTo: scanRootPath) },
            completedDirectories: completedLabels
        )
    }
}
