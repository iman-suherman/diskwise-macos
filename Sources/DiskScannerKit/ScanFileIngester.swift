import Foundation
import DatabaseKit

public struct ScanIngestSummary: Sendable {
    public let fileCount: Int
    public let indexedBytes: Int64

    public init(fileCount: Int, indexedBytes: Int64) {
        self.fileCount = fileCount
        self.indexedBytes = indexedBytes
    }
}

public final class ScanFileIngester: @unchecked Sendable {
    private let database: DiskWiseDatabase
    private let diskID: Int64
    private let batchSize: Int
    private var batch: [FileRecord] = []
    private var fileCount = 0
    private var indexedBytes: Int64 = 0

    public init(database: DiskWiseDatabase, diskID: Int64, batchSize: Int = 2_500) {
        self.database = database
        self.diskID = diskID
        self.batchSize = batchSize
        batch.reserveCapacity(batchSize)
    }

    public func beginScan(folderPathPrefix: String?) throws {
        try database.beginVolumeScan(forDiskID: diskID, folderPathPrefix: folderPathPrefix)
    }

    public func ingest(_ scanned: ScannedFile) throws {
        guard !scanned.isDirectory else { return }

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

        if batch.count >= batchSize {
            try flushBatch()
        }
    }

    public func finalize(scannedAt: Date) throws -> ScanIngestSummary {
        try flushBatch()
        try database.finalizeVolumeScan(forDiskID: diskID, scannedAt: scannedAt)
        return ScanIngestSummary(fileCount: fileCount, indexedBytes: indexedBytes)
    }

    private func flushBatch() throws {
        guard !batch.isEmpty else { return }
        try database.insertIndexedFiles(batch)
        batch.removeAll(keepingCapacity: true)
    }
}

public final class ScanVolumeFileSink: @unchecked Sendable {
    private let ingester: ScanFileIngester
    private var storedError: Error?
    private let lock = NSLock()

    public init(ingester: ScanFileIngester) {
        self.ingester = ingester
    }

    public func ingest(_ scanned: ScannedFile) {
        lock.lock()
        defer { lock.unlock() }
        guard storedError == nil else { return }
        do {
            try ingester.ingest(scanned)
        } catch {
            storedError = error
        }
    }

    public func checkForError() throws {
        lock.lock()
        defer { lock.unlock() }
        if let storedError {
            throw storedError
        }
    }

    public func beginScan(folderPathPrefix: String?) throws {
        try ingester.beginScan(folderPathPrefix: folderPathPrefix)
    }

    public func ingestGap(_ scanned: ScannedFile) throws {
        try ingester.ingest(scanned)
    }

    public func finalize(scannedAt: Date) throws -> ScanIngestSummary {
        try checkForError()
        return try ingester.finalize(scannedAt: scannedAt)
    }
}
