import Foundation
import DatabaseKit

public enum FileScannerError: Error, LocalizedError {
    case mountPathUnavailable(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .mountPathUnavailable(let path):
            return "Mount path is unavailable: \(path)"
        case .cancelled:
            return "Scan was cancelled."
        }
    }
}

public final class FileScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let batchSize: Int

    public init(fileManager: FileManager = .default, batchSize: Int = 250) {
        self.fileManager = fileManager
        self.batchSize = batchSize
    }

    public func scan(
        mountPath: URL,
        mode: ScanMode = .fast,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> [ScannedFile] {
        guard fileManager.fileExists(atPath: mountPath.path) else {
            throw FileScannerError.mountPathUnavailable(mountPath.path)
        }

        var results: [ScannedFile] = []
        var scannedCount = 0
        var indexedBytes: Int64 = 0

        if DirectorySizeOnlyPatterns.shouldProbeForHiddenDirectories(at: mountPath, mode: mode) {
            appendHiddenSummarizedDirectories(
                under: mountPath,
                to: &results,
                scannedCount: &scannedCount,
                indexedBytes: &indexedBytes,
                isCancelled: isCancelled
            )
        }

        let enumerator = fileManager.enumerator(
            at: mountPath,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let item = enumerator?.nextObject() as? URL {
            if isCancelled?() == true {
                throw FileScannerError.cancelled
            }

            let values = try item.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
            ])

            let isDirectory = values.isDirectory ?? false
            guard values.isRegularFile == true || isDirectory else {
                continue
            }

            if isDirectory {
                let name = item.lastPathComponent
                if DirectorySizeOnlyPatterns.shouldSummarizeDirectory(named: name, mode: mode) {
                    appendAggregateDirectory(
                        at: item,
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate,
                        lastAccessed: values.contentAccessDate,
                        to: &results,
                        scannedCount: &scannedCount,
                        indexedBytes: &indexedBytes
                    )
                    enumerator?.skipDescendants()
                    reportProgressIfNeeded(
                        scannedCount: scannedCount,
                        currentPath: item.path,
                        indexedBytes: indexedBytes,
                        onProgress: onProgress
                    )
                    continue
                }

                if DirectorySizeOnlyPatterns.shouldProbeForHiddenDirectories(at: item, mode: mode) {
                    appendHiddenSummarizedDirectories(
                        under: item,
                        to: &results,
                        scannedCount: &scannedCount,
                        indexedBytes: &indexedBytes,
                        isCancelled: isCancelled
                    )
                }
            }

            let size = Int64(values.fileSize ?? 0)
            if !isDirectory {
                indexedBytes += size
            }

            let scanned = ScannedFile(
                path: item.path,
                size: size,
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate,
                lastAccessed: values.contentAccessDate,
                extensionName: item.pathExtension.isEmpty ? nil : item.pathExtension.lowercased(),
                isDirectory: isDirectory
            )
            results.append(scanned)
            scannedCount += 1

            reportProgressIfNeeded(
                scannedCount: scannedCount,
                currentPath: item.path,
                indexedBytes: indexedBytes,
                onProgress: onProgress
            )
        }

        onProgress?(ScanProgress(scannedCount: scannedCount, currentPath: mountPath.path, bytesIndexed: indexedBytes))
        return results
    }

    private func appendAggregateDirectory(
        at url: URL,
        createdAt: Date?,
        modifiedAt: Date?,
        lastAccessed: Date?,
        to results: inout [ScannedFile],
        scannedCount: inout Int,
        indexedBytes: inout Int64
    ) {
        let size = FastDirectorySize.sizeOfDirectory(at: url.path, fileManager: fileManager)
        indexedBytes += size
        results.append(
            ScannedFile(
                path: url.path,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                lastAccessed: lastAccessed,
                extensionName: nil,
                isDirectory: false
            )
        )
        scannedCount += 1
    }

    private func appendHiddenSummarizedDirectories(
        under parent: URL,
        to results: inout [ScannedFile],
        scannedCount: inout Int,
        indexedBytes: inout Int64,
        isCancelled: (@Sendable () -> Bool)?
    ) {
        for name in DirectorySizeOnlyPatterns.hiddenFolderNames {
            if isCancelled?() == true { return }

            let child = parent.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let values = try? child.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
            ])

            appendAggregateDirectory(
                at: child,
                createdAt: values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastAccessed: values?.contentAccessDate,
                to: &results,
                scannedCount: &scannedCount,
                indexedBytes: &indexedBytes
            )
        }
    }

    private func reportProgressIfNeeded(
        scannedCount: Int,
        currentPath: String,
        indexedBytes: Int64,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) {
        if scannedCount.isMultiple(of: batchSize) {
            onProgress?(ScanProgress(scannedCount: scannedCount, currentPath: currentPath, bytesIndexed: indexedBytes))
        }
    }
}

public final class ScanEngine: @unchecked Sendable {
    private let scanner: FileScanner
    private let database: DiskWiseDatabase

    public init(database: DiskWiseDatabase, scanner: FileScanner = FileScanner()) {
        self.database = database
        self.scanner = scanner
    }

    public func scanVolume(
        name: String,
        mountPath: URL,
        scanRoot: URL? = nil,
        mode: ScanMode = .fast,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> ScanSummary {
        let start = Date()
        let root = scanRoot ?? mountPath
        let isFolderScan = root.standardizedFileURL.path != mountPath.standardizedFileURL.path

        let resourceValues = try mountPath.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ])

        var disk = try database.upsertDisk(
            DiskRecord(
                name: name,
                mountPath: mountPath.path,
                totalSize: Int64(resourceValues.volumeTotalCapacity ?? 0),
                freeSize: Int64(resourceValues.volumeAvailableCapacity ?? 0),
                scannedAt: Date()
            )
        )

        guard let diskID = disk.id else {
            throw DiskWiseDatabaseError.diskNotFound
        }

        if isFolderScan {
            try database.deleteFiles(forDiskID: diskID, underPath: root.path)
        } else {
            try database.deleteFiles(forDiskID: diskID)
        }

        let scannedFiles = try scanner.scan(
            mountPath: root,
            mode: mode,
            onProgress: onProgress,
            isCancelled: isCancelled
        )

        var batch: [FileRecord] = []
        var indexedBytes: Int64 = 0
        var fileCount = 0

        for scanned in scannedFiles where !scanned.isDirectory {
            let url = URL(fileURLWithPath: scanned.path)
            batch.append(
                FileRecord(
                    diskID: diskID,
                    path: scanned.path,
                    size: scanned.size,
                    mimeType: FileClassifier.mimeType(for: url),
                    category: FileClassifier.category(for: url, isDirectory: false),
                    createdAt: scanned.createdAt,
                    modifiedAt: scanned.modifiedAt,
                    lastAccessed: scanned.lastAccessed,
                    extensionName: scanned.extensionName
                )
            )
            indexedBytes += scanned.size
            fileCount += 1

            if batch.count >= 250 {
                try database.insertFiles(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            try database.insertFiles(batch)
        }

        disk.scannedAt = Date()
        _ = try database.upsertDisk(disk)

        return ScanSummary(
            diskID: diskID,
            scannedFiles: fileCount,
            indexedBytes: indexedBytes,
            duration: Date().timeIntervalSince(start),
            mode: mode
        )
    }
}
