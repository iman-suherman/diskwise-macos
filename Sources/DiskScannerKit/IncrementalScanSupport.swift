import Foundation
import DatabaseKit

public struct IncrementalScanContext: Sendable {
    public let diskID: Int64
    public let lookupCache: @Sendable (String) -> FolderScanCacheRecord?
    public let loadCachedFiles: @Sendable (String) -> [ScannedFile]
    public let onFolderCompleted: @Sendable (String, Date, Int, Int64) -> Void

    public init(
        diskID: Int64,
        lookupCache: @escaping @Sendable (String) -> FolderScanCacheRecord?,
        loadCachedFiles: @escaping @Sendable (String) -> [ScannedFile],
        onFolderCompleted: @escaping @Sendable (String, Date, Int, Int64) -> Void
    ) {
        self.diskID = diskID
        self.lookupCache = lookupCache
        self.loadCachedFiles = loadCachedFiles
        self.onFolderCompleted = onFolderCompleted
    }

    public static func make(
        database: DiskWiseDatabase,
        diskID: Int64
    ) -> IncrementalScanContext {
        IncrementalScanContext(
            diskID: diskID,
            lookupCache: { path in
                try? database.folderScanCache(forDiskID: diskID, path: path)
            },
            loadCachedFiles: { path in
                let records = (try? database.files(forDiskID: diskID, underPath: path)) ?? []
                return records.map { record in
                    ScannedFile(
                        path: record.path,
                        size: record.size,
                        createdAt: record.createdAt,
                        modifiedAt: record.modifiedAt,
                        lastAccessed: record.lastAccessed,
                        extensionName: record.extensionName,
                        isDirectory: false
                    )
                }
            },
            onFolderCompleted: { path, contentModifiedAt, fileCount, indexedBytes in
                let record = FolderScanCacheRecord(
                    diskID: diskID,
                    path: path,
                    contentModifiedAt: contentModifiedAt,
                    scannedAt: Date(),
                    fileCount: fileCount,
                    indexedBytes: indexedBytes
                )
                try? database.upsertFolderScanCache(record)
            }
        )
    }
}

enum IncrementalScanSupport {
    static func directoryContentModified(at url: URL, fileManager: FileManager) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        return try? url.resourceValues(forKeys: keys).contentModificationDate
    }

    static func shouldReuseCachedFolder(
        at url: URL,
        context: IncrementalScanContext?,
        fileManager: FileManager
    ) -> Bool {
        guard let context else { return false }
        guard let modifiedAt = directoryContentModified(at: url, fileManager: fileManager) else {
            return false
        }
        guard let cache = context.lookupCache(url.path) else { return false }
        return cache.contentModifiedAt == modifiedAt && cache.fileCount > 0
    }

    static func cachedFiles(
        at url: URL,
        context: IncrementalScanContext
    ) -> [ScannedFile] {
        context.loadCachedFiles(url.path)
    }

    static func recordFolderCompletion(
        at url: URL,
        results: [ScannedFile],
        context: IncrementalScanContext?,
        fileManager: FileManager
    ) {
        guard let context else { return }
        guard let modifiedAt = directoryContentModified(at: url, fileManager: fileManager) else { return }
        let fileResults = results.filter { !$0.isDirectory }
        let indexedBytes = fileResults.reduce(Int64(0)) { $0 + $1.size }
        context.onFolderCompleted(url.path, modifiedAt, fileResults.count, indexedBytes)
    }
}
