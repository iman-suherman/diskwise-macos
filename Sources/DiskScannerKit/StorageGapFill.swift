import Foundation
import DatabaseKit

/// Fills storage totals for directories that `FileManager` cannot fully enumerate
/// (permissions, TCC, sealed system paths) using `du` minus already-indexed bytes.
public enum StorageGapFill {
    private static let minimumGapBytes: Int64 = 1_048_576

    public static func appendGaps(
        scanRoot: URL,
        to results: inout [ScannedFile],
        fileManager: FileManager = .default,
        isCancelled: (@Sendable () -> Bool)? = nil,
        onProgress: (@Sendable (_ path: String, _ processed: Int, _ total: Int) -> Void)? = nil
    ) {
        let gaps = collectGaps(
            scanRoot: scanRoot,
            indexedBytesProvider: { directoryPath in
                indexedBytes(under: directoryPath, in: results)
            },
            fileManager: fileManager,
            isCancelled: isCancelled,
            onProgress: onProgress
        )
        results.append(contentsOf: gaps)
    }

    public static func collectGaps(
        scanRoot: URL,
        diskID: Int64,
        database: DiskWiseDatabase,
        fileManager: FileManager = .default,
        isCancelled: (@Sendable () -> Bool)? = nil,
        onProgress: (@Sendable (_ path: String, _ processed: Int, _ total: Int) -> Void)? = nil
    ) throws -> [ScannedFile] {
        try collectGaps(
            scanRoot: scanRoot,
            indexedBytesProvider: { directoryPath in
                try database.sumIndexedBytes(forDiskID: diskID, underPath: directoryPath)
            },
            fileManager: fileManager,
            isCancelled: isCancelled,
            onProgress: onProgress
        )
    }

    private static func collectGaps(
        scanRoot: URL,
        indexedBytesProvider: (String) throws -> Int64,
        fileManager: FileManager,
        isCancelled: (@Sendable () -> Bool)?,
        onProgress: (@Sendable (_ path: String, _ processed: Int, _ total: Int) -> Void)?
    ) rethrows -> [ScannedFile] {
        var gaps: [ScannedFile] = []
        let topLevelNames = (try? fileManager.contentsOfDirectory(atPath: scanRoot.path)) ?? []
        let topLevelChildren = topLevelNames.filter { !$0.hasPrefix(".") }

        for (index, name) in topLevelChildren.enumerated() {
            if isCancelled?() == true { return gaps }
            let child = scanRoot.appendingPathComponent(name, isDirectory: true)
            if let gap = try gapEntry(
                at: child,
                indexedBytesProvider: indexedBytesProvider,
                fileManager: fileManager
            ) {
                gaps.append(gap)
            }
            onProgress?(child.path, index + 1, topLevelChildren.count)
        }

        let usersDirectory = scanRoot.appendingPathComponent("Users", isDirectory: true)
        guard fileManager.fileExists(atPath: usersDirectory.path) else { return gaps }

        let userNames = (try? fileManager.contentsOfDirectory(atPath: usersDirectory.path)) ?? []
        let userChildren = userNames.filter { !$0.hasPrefix(".") }
        let usersTotal = userChildren.count

        for (index, name) in userChildren.enumerated() {
            if isCancelled?() == true { return gaps }
            let userDirectory = usersDirectory.appendingPathComponent(name, isDirectory: true)
            if let gap = try gapEntry(
                at: userDirectory,
                indexedBytesProvider: indexedBytesProvider,
                fileManager: fileManager
            ) {
                gaps.append(gap)
            }
            onProgress?(userDirectory.path, index + 1, usersTotal)
        }

        return gaps
    }

    private static func gapEntry(
        at directory: URL,
        indexedBytesProvider: (String) throws -> Int64,
        fileManager: FileManager
    ) rethrows -> ScannedFile? {
        let directoryPath = directory.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let diskUsage = FastDirectorySize.sizeOfDirectory(at: directoryPath, fileManager: fileManager)
        guard diskUsage > 0 else { return nil }

        let indexed = try indexedBytesProvider(directoryPath)
        let gap = diskUsage - indexed
        guard gap >= minimumGapBytes else { return nil }

        let values = try? directory.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
        ])

        return ScannedFile(
            path: directoryPath,
            size: gap,
            createdAt: values?.creationDate,
            modifiedAt: values?.contentModificationDate,
            lastAccessed: values?.contentAccessDate,
            extensionName: nil,
            isDirectory: false
        )
    }

    private static func indexedBytes(under directoryPath: String, in results: [ScannedFile]) -> Int64 {
        results.reduce(into: Int64(0)) { total, entry in
            guard !entry.isDirectory else { return }
            if entry.path == directoryPath || entry.path.hasPrefix(directoryPath + "/") {
                total += entry.size
            }
        }
    }
}
