import Foundation
import GRDB

public enum FileCategory: String, Codable, Sendable, CaseIterable {
    case video
    case photo
    case document
    case archive
    case application
    case backup
    case temporary
    case cache
    case development
    case downloads
    case containers
    case virtualMachines
    case other

    public var displayName: String {
        switch self {
        case .video, .photo: return "Media"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .application: return "Applications"
        case .backup: return "Backups"
        case .temporary: return "Temporary"
        case .cache: return "Caches"
        case .development: return "Development"
        case .downloads: return "Downloads"
        case .containers: return "Containers"
        case .virtualMachines: return "Virtual Machines"
        case .other: return "Other"
        }
    }

    /// Groups related categories for dashboard charts.
    public var chartGroup: String { displayName }

    /// Finer-grained label for drill-down rows.
    public var granularName: String {
        switch self {
        case .video: return "Videos"
        case .photo: return "Photos"
        default: return displayName
        }
    }

    public var systemImage: String {
        switch self {
        case .video, .photo: return "photo.on.rectangle.angled"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .application: return "app"
        case .backup: return "externaldrive.badge.timemachine"
        case .temporary: return "clock.badge.exclamationmark"
        case .cache: return "memorychip"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .downloads: return "arrow.down.circle"
        case .containers: return "shippingbox"
        case .virtualMachines: return "desktopcomputer"
        case .other: return "questionmark.folder"
        }
    }
}

public struct DiskRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "disks"

    public enum Columns {
        static let mountPath = Column(CodingKeys.mountPath)
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case name
        case mountPath = "mount_path"
        case totalSize = "total_size"
        case freeSize = "free_size"
        case scannedAt = "scanned_at"
    }

    public var id: Int64?
    public var name: String
    public var mountPath: String
    public var totalSize: Int64
    public var freeSize: Int64
    public var scannedAt: Date?

    public init(
        id: Int64? = nil,
        name: String,
        mountPath: String,
        totalSize: Int64,
        freeSize: Int64,
        scannedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.totalSize = totalSize
        self.freeSize = freeSize
        self.scannedAt = scannedAt
    }
}

public struct FileRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "files"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case diskID = "disk_id"
        case path
        case size
        case hash
        case mimeType = "mime_type"
        case category
        case subcategory
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case lastAccessed = "last_accessed"
        case extensionName = "extension_name"
    }

    public var id: Int64?
    public var diskID: Int64
    public var path: String
    public var size: Int64
    public var hash: String?
    public var mimeType: String?
    public var category: FileCategory
    public var subcategory: String?
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var lastAccessed: Date?
    public var extensionName: String?

    public init(
        id: Int64? = nil,
        diskID: Int64,
        path: String,
        size: Int64,
        hash: String? = nil,
        mimeType: String? = nil,
        category: FileCategory = .other,
        subcategory: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        lastAccessed: Date? = nil,
        extensionName: String? = nil
    ) {
        self.id = id
        self.diskID = diskID
        self.path = path
        self.size = size
        self.hash = hash
        self.mimeType = mimeType
        self.category = category
        self.subcategory = subcategory
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastAccessed = lastAccessed
        self.extensionName = extensionName
    }
}

public struct FolderScanCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "folder_scan_cache"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case diskID = "disk_id"
        case path
        case contentModifiedAt = "content_modified_at"
        case scannedAt = "scanned_at"
        case fileCount = "file_count"
        case indexedBytes = "indexed_bytes"
    }

    public var id: Int64?
    public var diskID: Int64
    public var path: String
    public var contentModifiedAt: Date
    public var scannedAt: Date
    public var fileCount: Int
    public var indexedBytes: Int64

    public init(
        id: Int64? = nil,
        diskID: Int64,
        path: String,
        contentModifiedAt: Date,
        scannedAt: Date,
        fileCount: Int,
        indexedBytes: Int64
    ) {
        self.id = id
        self.diskID = diskID
        self.path = path
        self.contentModifiedAt = contentModifiedAt
        self.scannedAt = scannedAt
        self.fileCount = fileCount
        self.indexedBytes = indexedBytes
    }
}

public struct FileMetadataRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "file_metadata"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case fileID = "file_id"
        case metadataType = "metadata_type"
        case payloadJSON = "payload_json"
    }

    public var id: Int64?
    public var fileID: Int64
    public var metadataType: String
    public var payloadJSON: String

    public init(id: Int64? = nil, fileID: Int64, metadataType: String, payloadJSON: String) {
        self.id = id
        self.fileID = fileID
        self.metadataType = metadataType
        self.payloadJSON = payloadJSON
    }
}

public struct DuplicateGroupRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "duplicate_groups"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case detectionLevel = "detection_level"
        case fingerprint
        case totalSize = "total_size"
        case fileCount = "file_count"
        case createdAt = "created_at"
    }

    public var id: Int64?
    public var detectionLevel: Int
    public var fingerprint: String
    public var totalSize: Int64
    public var fileCount: Int
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        detectionLevel: Int,
        fingerprint: String,
        totalSize: Int64,
        fileCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.detectionLevel = detectionLevel
        self.fingerprint = fingerprint
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.createdAt = createdAt
    }
}

public struct DuplicateMemberRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "duplicate_members"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case groupID = "group_id"
        case fileID = "file_id"
    }

    public var id: Int64?
    public var groupID: Int64
    public var fileID: Int64

    public init(id: Int64? = nil, groupID: Int64, fileID: Int64) {
        self.id = id
        self.groupID = groupID
        self.fileID = fileID
    }
}

public struct RecommendationRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "recommendations"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case type
        case title
        case estimatedSavings = "estimated_savings"
        case reason
        case status
        case createdAt = "created_at"
    }

    public var id: Int64?
    public var type: String
    public var title: String
    public var estimatedSavings: Int64
    public var reason: String
    public var status: String
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        type: String,
        title: String,
        estimatedSavings: Int64,
        reason: String,
        status: String = "pending",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.estimatedSavings = estimatedSavings
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
    }
}

public struct CategorySummary: Sendable {
    public let category: FileCategory
    public let totalSize: Int64
    public let fileCount: Int

    public init(category: FileCategory, totalSize: Int64, fileCount: Int) {
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
    }
}

public struct SpaceConsumer: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let totalSize: Int64
    public let fileCount: Int

    public init(name: String, totalSize: Int64, fileCount: Int) {
        self.name = name
        self.totalSize = totalSize
        self.fileCount = fileCount
    }
}

public struct StorageOverview: Sendable {
    public let totalSize: Int64
    public let fileCount: Int
    public let categorySummaries: [CategorySummary]
    public let duplicateSavings: Int64
    public let oldFileSize: Int64

    public init(
        totalSize: Int64,
        fileCount: Int,
        categorySummaries: [CategorySummary],
        duplicateSavings: Int64,
        oldFileSize: Int64
    ) {
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.categorySummaries = categorySummaries
        self.duplicateSavings = duplicateSavings
        self.oldFileSize = oldFileSize
    }
}
