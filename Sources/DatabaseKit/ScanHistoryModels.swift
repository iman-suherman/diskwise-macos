import Foundation
import GRDB

public struct ScanHistorySnapshot: Sendable, Codable {
    public let categorySummaries: [CategorySummary]
    public let topConsumers: [SpaceConsumer]

    public init(categorySummaries: [CategorySummary], topConsumers: [SpaceConsumer]) {
        self.categorySummaries = categorySummaries
        self.topConsumers = topConsumers
    }

    public var majorCategories: [CategorySummary] {
        Array(categorySummaries.sorted { $0.totalSize > $1.totalSize }.prefix(5))
    }
}

public struct ScanHistoryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "scan_history"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case diskID = "disk_id"
        case scanMode = "scan_mode"
        case scannedAt = "scanned_at"
        case fileCount = "file_count"
        case indexedBytes = "indexed_bytes"
        case freeBytes = "free_bytes"
        case durationSeconds = "duration_seconds"
        case snapshotJSON = "snapshot_json"
    }

    public var id: Int64?
    public var diskID: Int64
    public var scanMode: String
    public var scannedAt: Date
    public var fileCount: Int
    public var indexedBytes: Int64
    public var freeBytes: Int64
    public var durationSeconds: Double
    public var snapshotJSON: String

    public init(
        id: Int64? = nil,
        diskID: Int64,
        scanMode: String,
        scannedAt: Date = Date(),
        fileCount: Int,
        indexedBytes: Int64,
        freeBytes: Int64,
        durationSeconds: Double,
        snapshotJSON: String
    ) {
        self.id = id
        self.diskID = diskID
        self.scanMode = scanMode
        self.scannedAt = scannedAt
        self.fileCount = fileCount
        self.indexedBytes = indexedBytes
        self.freeBytes = freeBytes
        self.durationSeconds = durationSeconds
        self.snapshotJSON = snapshotJSON
    }

    public func decodedSnapshot() -> ScanHistorySnapshot? {
        guard let data = snapshotJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ScanHistorySnapshot.self, from: data)
    }

    public static func encodeSnapshot(_ snapshot: ScanHistorySnapshot) -> String? {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
