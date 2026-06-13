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
        tieredVolumeScan: Bool = false,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> [ScannedFile] {
        guard fileManager.fileExists(atPath: mountPath.path) else {
            throw FileScannerError.mountPathUnavailable(mountPath.path)
        }

        if tieredVolumeScan && mode == .fast {
            return try scanTieredVolume(
                mountPath: mountPath,
                mode: mode,
                onProgress: onProgress,
                isCancelled: isCancelled
            )
        }

        return try scanEnumerated(
            mountPath: mountPath,
            mode: mode,
            onProgress: onProgress,
            isCancelled: isCancelled
        )
    }

    private func scanTieredVolume(
        mountPath: URL,
        mode: ScanMode,
        onProgress: (@Sendable (ScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> [ScannedFile] {
        let childNames = (try? fileManager.contentsOfDirectory(atPath: mountPath.path)) ?? []
        let sortedChildren = childNames.sorted()
        let directoryChildren = sortedChildren.filter { name in
            var isDirectory: ObjCBool = false
            let path = mountPath.appendingPathComponent(name).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        guard !directoryChildren.isEmpty else {
            return try scanEnumerated(
                mountPath: mountPath,
                mode: mode,
                onProgress: onProgress,
                isCancelled: isCancelled
            )
        }

        let summarizeNames = directoryChildren.filter(VolumeTieredScan.shouldSummarizeTopLevelDirectory(named:))
        let drillRoots = directoryChildren
            .filter { !VolumeTieredScan.shouldSummarizeTopLevelDirectory(named: $0) }
            .map { mountPath.appendingPathComponent($0, isDirectory: true) }

        var drillDirectories: [URL] = []
        for drillRoot in drillRoots {
            if isCancelled?() == true {
                throw FileScannerError.cancelled
            }
            drillDirectories.append(
                contentsOf: VolumeTieredScan.concurrentDrillDirectories(at: drillRoot, fileManager: fileManager)
            )
        }

        let identifiedDirectories =
            summarizeNames +
            drillDirectories.map { ScanConcurrency.displayLabel(for: $0.path, relativeTo: mountPath.path) }
        let total = identifiedDirectories.count
        let maxConcurrency = ScanConcurrency.maxParallelTasks

        var results: [ScannedFile] = []
        var scannedCount = 0
        var indexedBytes: Int64 = 0

        let aggregator = ScanProgressAggregator(
            scannedCount: scannedCount,
            indexedBytes: indexedBytes,
            identifiedDirectories: identifiedDirectories,
            directoriesTotal: total,
            maxConcurrency: maxConcurrency,
            scanRootPath: mountPath.path,
            onProgress: onProgress
        )

        aggregator.emit(
            currentPath: mountPath.path,
            operation: .preparing,
            detail: "Identified \(total.formatted()) folders · up to \(maxConcurrency) parallel scans"
        )

        if !summarizeNames.isEmpty {
            let summarizeResults = try summarizeTopLevelDirectories(
                names: summarizeNames,
                under: mountPath,
                aggregator: aggregator,
                isCancelled: isCancelled
            )
            results.append(contentsOf: summarizeResults.entries)
            scannedCount = summarizeResults.scannedCount
            indexedBytes = summarizeResults.indexedBytes
        }

        if !drillDirectories.isEmpty {
            let drillResults = try scanDirectoriesConcurrently(
                directories: drillDirectories,
                mode: mode,
                aggregator: aggregator,
                isCancelled: isCancelled
            )
            results.append(contentsOf: drillResults)
            scannedCount += drillResults.filter { !$0.isDirectory }.count
            indexedBytes += drillResults.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
        }

        aggregator.emit(
            currentPath: mountPath.path,
            operation: .enumeratingFiles,
            detail: "Finished mapping \(total.formatted()) folders"
        )

        return results
    }

    private func scanDirectoriesConcurrently(
        directories: [URL],
        mode: ScanMode,
        aggregator: ScanProgressAggregator,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> [ScannedFile] {
        let maxConcurrency = ScanConcurrency.maxParallelTasks
        let semaphore = DispatchSemaphore(value: maxConcurrency)
        let group = DispatchGroup()
        let lock = NSLock()
        var combined: [ScannedFile] = []
        var thrownError: Error?

        for directory in directories {
            if isCancelled?() == true {
                throw FileScannerError.cancelled
            }

            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { group.leave() }

                guard let self else { return }
                semaphore.wait()
                defer { semaphore.signal() }

                if isCancelled?() == true { return }

                let label = ScanConcurrency.displayLabel(
                    for: directory.path,
                    relativeTo: aggregator.scanRootPathForDisplay
                )
                aggregator.willBegin(
                    directory.path,
                    operation: .enumeratingFiles,
                    detail: "Indexing \(label)"
                )

                do {
                    let batch = try self.scanEnumerated(
                        mountPath: directory,
                        mode: mode,
                        onProgress: nil,
                        isCancelled: isCancelled
                    )
                    lock.lock()
                    combined.append(contentsOf: batch)
                    lock.unlock()
                    aggregator.didComplete(
                        directory.path,
                        results: batch,
                        operation: .enumeratingFiles,
                        detail: "Finished \(label)"
                    )
                } catch {
                    lock.lock()
                    if thrownError == nil {
                        thrownError = error
                    }
                    lock.unlock()
                }
            }
        }

        group.wait()

        if let thrownError {
            throw thrownError
        }
        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        return combined
    }

    private struct SummarizeBatchResult {
        let entries: [ScannedFile]
        let scannedCount: Int
        let indexedBytes: Int64
    }

    private func summarizeTopLevelDirectories(
        names: [String],
        under mountPath: URL,
        aggregator: ScanProgressAggregator,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> SummarizeBatchResult {
        var entries: [ScannedFile] = []
        var count = 0
        var bytes: Int64 = 0
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: names.count) { index in

            let name = names[index]
            let childURL = mountPath.appendingPathComponent(name, isDirectory: true)
            aggregator.willBegin(
                childURL.path,
                operation: .sizingDirectory,
                detail: "Sizing \(name) with disk usage"
            )

            let values = try? childURL.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
            ])
            let size = FastDirectorySize.sizeOfDirectory(at: childURL.path, fileManager: fileManager)
            let entry = ScannedFile(
                path: childURL.path,
                size: size,
                createdAt: values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastAccessed: values?.contentAccessDate,
                extensionName: nil,
                isDirectory: false
            )

            lock.lock()
            entries.append(entry)
            count += 1
            bytes += size
            lock.unlock()

            aggregator.didComplete(
                childURL.path,
                results: [entry],
                operation: .sizingDirectory,
                detail: "Sized \(name)"
            )
        }

        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        return SummarizeBatchResult(entries: entries, scannedCount: count, indexedBytes: bytes)
    }

    private func scanEnumerated(
        mountPath: URL,
        mode: ScanMode,
        onProgress: (@Sendable (ScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> [ScannedFile] {
        var results: [ScannedFile] = []
        var scannedCount = 0
        var indexedBytes: Int64 = 0

        if DirectorySizeOnlyPatterns.shouldProbeForHiddenDirectories(at: mountPath, mode: mode) {
            reportProgress(
                scannedCount: scannedCount,
                currentPath: mountPath.path,
                indexedBytes: indexedBytes,
                operation: .probingHidden,
                detail: "Checking for hidden dependency folders",
                force: true,
                onProgress: onProgress
            )
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
                .isPackageKey,
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
                .isPackageKey,
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
                if PackageBundlePatterns.shouldSummarizePackage(at: item, isPackage: values.isPackage) {
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
                        operation: .sizingDirectory,
                        detail: "Sized app bundle \(item.lastPathComponent)",
                        onProgress: onProgress
                    )
                    continue
                }

                let name = item.lastPathComponent
                if DirectorySizeOnlyPatterns.shouldSummarizeDirectory(at: item, named: name, mode: mode) {
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
                        operation: .sizingDirectory,
                        detail: "Sized \(name) in one step",
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
                operation: .enumeratingFiles,
                detail: nil,
                onProgress: onProgress
            )
        }

        reportProgress(
            scannedCount: scannedCount,
            currentPath: mountPath.path,
            indexedBytes: indexedBytes,
            operation: .enumeratingFiles,
            detail: "Finished indexing \(mountPath.lastPathComponent)",
            force: true,
            onProgress: onProgress
        )
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
        operation: ScanOperation,
        detail: String?,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) {
        if scannedCount.isMultiple(of: batchSize) {
            reportProgress(
                scannedCount: scannedCount,
                currentPath: currentPath,
                indexedBytes: indexedBytes,
                operation: operation,
                detail: detail,
                onProgress: onProgress
            )
        }
    }

    private func reportProgress(
        scannedCount: Int,
        currentPath: String,
        indexedBytes: Int64,
        operation: ScanOperation,
        detail: String? = nil,
        directoriesProcessed: Int? = nil,
        directoriesTotal: Int? = nil,
        force: Bool = false,
        onProgress: (@Sendable (ScanProgress) -> Void)?
    ) {
        guard force || scannedCount.isMultiple(of: batchSize) else { return }
        onProgress?(
            ScanProgress(
                scannedCount: scannedCount,
                currentPath: currentPath,
                bytesIndexed: indexedBytes,
                operation: operation,
                detail: detail,
                directoriesProcessed: directoriesProcessed,
                directoriesTotal: directoriesTotal
            )
        )
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
        let volumeRoot = mountPath.standardizedFileURL
        let defaultRoot = VolumeScanRoot.effectiveScanRoot(for: volumeRoot)
        let root = (scanRoot ?? defaultRoot).standardizedFileURL
        let isFolderScan = root.path != volumeRoot.path
        let tieredVolumeScan = VolumeTieredScan.shouldUseTieredScan(
            at: root,
            mode: mode,
            isFolderScan: isFolderScan
        )

        let resourceValues = try volumeRoot.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ])

        let existingDisk = try database.allDisks().first { $0.mountPath == volumeRoot.path }
        var disk = try database.upsertDisk(
            DiskRecord(
                name: name,
                mountPath: volumeRoot.path,
                totalSize: Int64(resourceValues.volumeTotalCapacity ?? 0),
                freeSize: Int64(resourceValues.volumeAvailableCapacity ?? 0),
                scannedAt: existingDisk?.scannedAt
            )
        )

        guard let diskID = disk.id else {
            throw DiskWiseDatabaseError.diskNotFound
        }

        var scannedFiles = try scanner.scan(
            mountPath: root,
            mode: mode,
            tieredVolumeScan: tieredVolumeScan,
            onProgress: onProgress,
            isCancelled: isCancelled
        )

        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        let gapScannedCount = scannedFiles.filter { !$0.isDirectory }.count
        let gapIndexedBytes = scannedFiles.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size) }
        onProgress?(
            ScanProgress(
                scannedCount: gapScannedCount,
                currentPath: root.path,
                bytesIndexed: gapIndexedBytes,
                operation: .fillingGaps,
                detail: "Measuring folders that could not be fully indexed"
            )
        )

        StorageGapFill.appendGaps(
            scanRoot: root,
            to: &scannedFiles,
            isCancelled: isCancelled,
            onProgress: { path, processed, total in
                onProgress?(
                    ScanProgress(
                        scannedCount: gapScannedCount,
                        currentPath: path,
                        bytesIndexed: gapIndexedBytes,
                        operation: .fillingGaps,
                        detail: "Filling coverage gaps (\(processed)/\(total))",
                        directoriesProcessed: processed,
                        directoriesTotal: total
                    )
                )
            }
        )

        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        var fileRecords: [FileRecord] = []
        fileRecords.reserveCapacity(scannedFiles.count)
        var indexedBytes: Int64 = 0
        var fileCount = 0

        for scanned in scannedFiles where !scanned.isDirectory {
            let url = URL(fileURLWithPath: scanned.path)
            fileRecords.append(
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
        }

        let scannedAt = Date()
        try database.replaceIndexedFiles(
            forDiskID: diskID,
            files: fileRecords,
            folderPathPrefix: isFolderScan ? root.path : nil,
            scannedAt: scannedAt
        )

        return ScanSummary(
            diskID: diskID,
            scannedFiles: fileCount,
            indexedBytes: indexedBytes,
            duration: Date().timeIntervalSince(start),
            mode: mode
        )
    }
}
