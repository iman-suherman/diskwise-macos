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

    private func record(
        _ scanned: ScannedFile,
        in results: inout [ScannedFile],
        onFile: (@Sendable (ScannedFile) -> Void)?
    ) {
        onFile?(scanned)
        if onFile == nil {
            results.append(scanned)
        }
    }

    public func scan(
        mountPath: URL,
        mode: ScanMode = .fast,
        tieredVolumeScan: Bool = false,
        incrementalContext: IncrementalScanContext? = nil,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onFile: (@Sendable (ScannedFile) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> [ScannedFile] {
        guard fileManager.fileExists(atPath: mountPath.path) else {
            throw FileScannerError.mountPathUnavailable(mountPath.path)
        }

        if IncrementalScanSupport.shouldReuseCachedFolder(
            at: mountPath,
            context: incrementalContext,
            fileManager: fileManager
        ), let incrementalContext {
            let cached = IncrementalScanSupport.cachedFiles(at: mountPath, context: incrementalContext)
            if !cached.isEmpty {
                reportProgress(
                    scannedCount: cached.count,
                    currentPath: mountPath.path,
                    indexedBytes: cached.reduce(0) { $0 + $1.size },
                    operation: .enumeratingFiles,
                    detail: "Reused cached index for unchanged folder",
                    force: true,
                    onProgress: onProgress
                )
                if let onFile {
                    for file in cached {
                        onFile(file)
                    }
                    return []
                }
                return cached
            }
        }

        if tieredVolumeScan && mode == .fast {
            return try scanTieredVolume(
                mountPath: mountPath,
                mode: mode,
                incrementalContext: incrementalContext,
                onProgress: onProgress,
                onFile: onFile,
                isCancelled: isCancelled
            )
        }

        let results = try scanEnumerated(
            mountPath: mountPath,
            mode: mode,
            onProgress: onProgress,
            onFile: onFile,
            isCancelled: isCancelled
        )
        if onFile == nil {
            IncrementalScanSupport.recordFolderCompletion(
                at: mountPath,
                results: results,
                context: incrementalContext,
                fileManager: fileManager
            )
        }
        return results
    }

    private func scanTieredVolume(
        mountPath: URL,
        mode: ScanMode,
        incrementalContext: IncrementalScanContext?,
        onProgress: (@Sendable (ScanProgress) -> Void)?,
        onFile: (@Sendable (ScannedFile) -> Void)?,
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
                onFile: onFile,
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
                contentsOf: VolumeTieredScan.sequentialDrillDirectories(at: drillRoot, fileManager: fileManager)
            )
        }

        let identifiedDirectories =
            summarizeNames +
            drillDirectories.map { ScanConcurrency.displayLabel(for: $0.path, relativeTo: mountPath.path) }
        let total = identifiedDirectories.count
        var results: [ScannedFile] = []
        var scannedCount = 0
        var indexedBytes: Int64 = 0

        let aggregator = ScanProgressAggregator(
            scannedCount: scannedCount,
            indexedBytes: indexedBytes,
            identifiedDirectories: identifiedDirectories,
            directoriesTotal: total,
            scanRootPath: mountPath.path,
            onProgress: onProgress
        )

        aggregator.emit(
            currentPath: mountPath.path,
            operation: .preparing,
            detail: "Identified \(total.formatted()) folders"
        )

        if !summarizeNames.isEmpty {
            let summarizeResults = try summarizeTopLevelDirectories(
                names: summarizeNames,
                under: mountPath,
                incrementalContext: incrementalContext,
                aggregator: aggregator,
                onFile: onFile,
                isCancelled: isCancelled
            )
            if onFile == nil {
                results.append(contentsOf: summarizeResults.entries)
            }
            scannedCount = summarizeResults.scannedCount
            indexedBytes = summarizeResults.indexedBytes
        }

        if !drillDirectories.isEmpty {
            let drillResults = try scanDirectoriesSequentially(
                directories: drillDirectories,
                mode: mode,
                incrementalContext: incrementalContext,
                aggregator: aggregator,
                onFile: onFile,
                isCancelled: isCancelled
            )
            if onFile == nil {
                results.append(contentsOf: drillResults)
            }
            scannedCount += drillResults.filter { !$0.isDirectory }.count
            indexedBytes += drillResults.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
        }

        aggregator.emit(
            currentPath: mountPath.path,
            operation: .enumeratingFiles,
            detail: "Finished mapping \(total.formatted()) folders"
        )

        if onFile == nil {
            IncrementalScanSupport.recordFolderCompletion(
                at: mountPath,
                results: results,
                context: incrementalContext,
                fileManager: fileManager
            )
        }

        return results
    }

    private func scanDirectoriesSequentially(
        directories: [URL],
        mode: ScanMode,
        incrementalContext: IncrementalScanContext?,
        aggregator: ScanProgressAggregator,
        onFile: (@Sendable (ScannedFile) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> [ScannedFile] {
        var combined: [ScannedFile] = []

        for directory in directories {
            if isCancelled?() == true {
                throw FileScannerError.cancelled
            }

            let label = ScanConcurrency.displayLabel(
                for: directory.path,
                relativeTo: aggregator.scanRootPathForDisplay
            )

            if IncrementalScanSupport.shouldReuseCachedFolder(
                at: directory,
                context: incrementalContext,
                fileManager: fileManager
            ), let incrementalContext {
                aggregator.willBegin(
                    directory.path,
                    operation: .enumeratingFiles,
                    detail: "Reusing cached index for \(label)"
                )
                let batch = IncrementalScanSupport.cachedFiles(at: directory, context: incrementalContext)
                if let onFile {
                    for file in batch {
                        onFile(file)
                    }
                } else {
                    combined.append(contentsOf: batch)
                }
                aggregator.didComplete(
                    directory.path,
                    results: batch,
                    operation: .enumeratingFiles,
                    detail: "Skipped unchanged \(label)"
                )
                continue
            }

            aggregator.willBegin(
                directory.path,
                operation: .enumeratingFiles,
                detail: "Indexing \(label)"
            )

            let batch = try scanEnumerated(
                mountPath: directory,
                mode: mode,
                onProgress: nil,
                onFile: onFile,
                isCancelled: isCancelled
            )
            if onFile == nil {
                combined.append(contentsOf: batch)
                IncrementalScanSupport.recordFolderCompletion(
                    at: directory,
                    results: batch,
                    context: incrementalContext,
                    fileManager: fileManager
                )
            }
            aggregator.didComplete(
                directory.path,
                results: batch,
                operation: .enumeratingFiles,
                detail: "Finished \(label)"
            )
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
        incrementalContext: IncrementalScanContext?,
        aggregator: ScanProgressAggregator,
        onFile: (@Sendable (ScannedFile) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> SummarizeBatchResult {
        var entries: [ScannedFile] = []
        var count = 0
        var bytes: Int64 = 0

        for name in names {
            let childURL = mountPath.appendingPathComponent(name, isDirectory: true)

            if IncrementalScanSupport.shouldReuseCachedFolder(
                at: childURL,
                context: incrementalContext,
                fileManager: fileManager
            ), let incrementalContext {
                aggregator.willBegin(
                    childURL.path,
                    operation: .sizingDirectory,
                    detail: "Reusing cached index for \(name)"
                )
                let cached = IncrementalScanSupport.cachedFiles(at: childURL, context: incrementalContext)
                if let onFile {
                    for file in cached {
                        onFile(file)
                    }
                } else {
                    entries.append(contentsOf: cached)
                }
                count += cached.count
                bytes += cached.reduce(0) { $0 + $1.size }
                aggregator.didComplete(
                    childURL.path,
                    results: cached,
                    operation: .sizingDirectory,
                    detail: "Skipped unchanged \(name)"
                )
                continue
            }

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

            record(entry, in: &entries, onFile: onFile)
            count += 1
            bytes += size

            if onFile == nil {
                IncrementalScanSupport.recordFolderCompletion(
                    at: childURL,
                    results: [entry],
                    context: incrementalContext,
                    fileManager: fileManager
                )
            }
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
        onFile: (@Sendable (ScannedFile) -> Void)? = nil,
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
                onFile: onFile,
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
                        indexedBytes: &indexedBytes,
                        onFile: onFile
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
                        indexedBytes: &indexedBytes,
                        onFile: onFile
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
                        onFile: onFile,
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
            record(scanned, in: &results, onFile: onFile)
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
        indexedBytes: inout Int64,
        onFile: (@Sendable (ScannedFile) -> Void)? = nil
    ) {
        let size = FastDirectorySize.sizeOfDirectory(at: url.path, fileManager: fileManager)
        indexedBytes += size
        record(
            ScannedFile(
                path: url.path,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                lastAccessed: lastAccessed,
                extensionName: nil,
                isDirectory: false
            ),
            in: &results,
            onFile: onFile
        )
        scannedCount += 1
    }

    private func appendHiddenSummarizedDirectories(
        under parent: URL,
        to results: inout [ScannedFile],
        scannedCount: inout Int,
        indexedBytes: inout Int64,
        onFile: (@Sendable (ScannedFile) -> Void)? = nil,
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
                indexedBytes: &indexedBytes,
                onFile: onFile
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
    private let pythonRunner: PythonScanRunner?
    private let database: DiskWiseDatabase

    public init(
        database: DiskWiseDatabase,
        scanner: FileScanner = FileScanner(),
        pythonScannerScript: URL? = nil
    ) {
        self.database = database
        self.scanner = scanner
        if let pythonScannerScript {
            self.pythonRunner = PythonScanRunner(scriptURL: pythonScannerScript)
        } else {
            self.pythonRunner = nil
        }
    }

    public func scanVolume(
        name: String,
        mountPath: URL,
        scanRoot: URL? = nil,
        mode: ScanMode = .fast,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onLogLine: (@Sendable (String) -> Void)? = nil,
        onScanSessionStarted: (@Sendable (PythonScanSession) -> Void)? = nil,
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

        let scannedVolume = MountedVolume(
            name: name,
            mountPath: volumeRoot.path,
            totalSize: Int64(resourceValues.volumeTotalCapacity ?? 0),
            freeSize: Int64(resourceValues.volumeAvailableCapacity ?? 0),
            isInternal: VolumeDiscovery.isSystemVolume(mountPath: volumeRoot.path),
            isRemovable: false
        )
        let excludePathPrefixes = VolumeFileScope.nestedVolumeScanExclusions(
            forScannedVolume: scannedVolume,
            allVolumes: VolumeDiscovery.mountedVolumes()
        )

        let incrementalContext = IncrementalScanContext.make(database: database, diskID: diskID)
        let sink = ScanVolumeFileSink(ingester: ScanFileIngester(database: database, diskID: diskID))
        try sink.beginScan(folderPathPrefix: isFolderScan ? root.path : nil)

        let ingestFile: @Sendable (ScannedFile) -> Void = { scanned in
            sink.ingest(scanned)
        }

        if let pythonRunner {
            let session = try pythonRunner.makeSession()
            onScanSessionStarted?(session)
            _ = try pythonRunner.scan(
                mountPath: root,
                mode: mode,
                tieredVolumeScan: tieredVolumeScan,
                excludePathPrefixes: excludePathPrefixes,
                session: session,
                onProgress: onProgress,
                onLogLine: onLogLine,
                onFile: ingestFile,
                isCancelled: isCancelled
            )
        } else {
            _ = try scanner.scan(
                mountPath: root,
                mode: mode,
                tieredVolumeScan: tieredVolumeScan,
                incrementalContext: incrementalContext,
                onProgress: onProgress,
                onFile: ingestFile,
                isCancelled: isCancelled
            )
        }

        try sink.checkForError()

        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        onProgress?(
            ScanProgress(
                scannedCount: 0,
                currentPath: root.path,
                bytesIndexed: 0,
                operation: .fillingGaps,
                detail: "Measuring folders that could not be fully indexed"
            )
        )

        let gapFiles = try StorageGapFill.collectGaps(
            scanRoot: root,
            diskID: diskID,
            database: database,
            isCancelled: isCancelled,
            onProgress: { path, processed, total in
                onProgress?(
                    ScanProgress(
                        scannedCount: 0,
                        currentPath: path,
                        bytesIndexed: 0,
                        operation: .fillingGaps,
                        detail: "Filling coverage gaps (\(processed)/\(total))",
                        directoriesProcessed: processed,
                        directoriesTotal: total
                    )
                )
            }
        )

        for gap in gapFiles {
            try sink.ingestGap(gap)
        }

        if isCancelled?() == true {
            throw FileScannerError.cancelled
        }

        let ingestSummary = try sink.finalize(scannedAt: Date())
        database.releaseMemory()

        return ScanSummary(
            diskID: diskID,
            scannedFiles: ingestSummary.fileCount,
            indexedBytes: ingestSummary.indexedBytes,
            duration: Date().timeIntervalSince(start),
            mode: mode
        )
    }

    public func cancelActiveScan() {
        pythonRunner?.cancelRunningScan()
    }
}
