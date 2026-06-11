import Foundation
import GRDB

public enum DiskWiseDatabaseError: Error, LocalizedError {
    case invalidPath
    case diskNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Database path is invalid."
        case .diskNotFound:
            return "Disk record was not found."
        }
    }
}

public final class DiskWiseDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path.path)
        try DiskWiseMigrator.make().migrate(dbQueue)
    }

    public static func defaultURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("DiskWise/diskwise.sqlite")
    }

    public func upsertDisk(_ disk: DiskRecord) throws -> DiskRecord {
        try dbQueue.write { db in
            if let existing = try DiskRecord.fetchOne(db, sql: "SELECT * FROM disks WHERE mount_path = ?", arguments: [disk.mountPath]) {
                var updated = disk
                updated.id = existing.id
                try updated.update(db)
                return updated
            }

            var inserted = disk
            try inserted.insert(db)
            return inserted
        }
    }

    public func allDisks() throws -> [DiskRecord] {
        try dbQueue.read { db in
            try DiskRecord.fetchAll(db, sql: "SELECT * FROM disks ORDER BY name ASC")
        }
    }

    public func insertFiles(_ files: [FileRecord]) throws {
        guard !files.isEmpty else { return }

        try dbQueue.write { db in
            for file in files {
                try file.insert(db, onConflict: .replace)
            }
        }
    }

    public func deleteFiles(forDiskID diskID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM files WHERE disk_id = ?", arguments: [diskID])
        }
    }

    public func indexedFileCount(forDiskID diskID: Int64) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM files WHERE disk_id = ?",
                arguments: [diskID]
            ) ?? 0
        }
    }

    public func deleteFiles(forDiskID diskID: Int64, underPath pathPrefix: String) throws {
        let normalized = pathPrefix.hasSuffix("/") ? String(pathPrefix.dropLast()) : pathPrefix
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM files WHERE disk_id = ? AND (path = ? OR path LIKE ?)",
                arguments: [diskID, normalized, normalized + "/%"]
            )
        }
    }

    public func files(forDiskID diskID: Int64, limit: Int = 500) throws -> [FileRecord] {
        try dbQueue.read { db in
            try FileRecord.fetchAll(
                db,
                sql: "SELECT * FROM files WHERE disk_id = ? ORDER BY size DESC LIMIT ?",
                arguments: [diskID, limit]
            )
        }
    }

    public func files(withSize size: Int64) throws -> [FileRecord] {
        try dbQueue.read { db in
            try FileRecord.fetchAll(db, sql: "SELECT * FROM files WHERE size = ?", arguments: [size])
        }
    }

    public func files(withHash hash: String) throws -> [FileRecord] {
        try dbQueue.read { db in
            try FileRecord.fetchAll(db, sql: "SELECT * FROM files WHERE hash = ?", arguments: [hash])
        }
    }

    public func updateHash(forFileID fileID: Int64, hash: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE files SET hash = ? WHERE id = ?", arguments: [hash, fileID])
        }
    }

    public func insertMetadata(_ metadata: FileMetadataRecord) throws {
        try dbQueue.write { db in
            try metadata.insert(db, onConflict: .replace)
        }
    }

    public func createDuplicateGroup(_ group: DuplicateGroupRecord, fileIDs: [Int64]) throws -> DuplicateGroupRecord {
        try dbQueue.write { db in
            var insertedGroup = group
            try insertedGroup.insert(db)
            guard let groupID = insertedGroup.id else {
                return insertedGroup
            }

            for fileID in fileIDs {
                let member = DuplicateMemberRecord(groupID: groupID, fileID: fileID)
                try member.insert(db)
            }

            return insertedGroup
        }
    }

    public func duplicateGroups(forDiskID diskID: Int64, limit: Int = 100) throws -> [DuplicateGroupRecord] {
        try dbQueue.read { db in
            try DuplicateGroupRecord.fetchAll(
                db,
                sql: """
                SELECT DISTINCT duplicate_groups.*
                FROM duplicate_groups
                JOIN duplicate_members ON duplicate_members.group_id = duplicate_groups.id
                JOIN files ON files.id = duplicate_members.file_id
                WHERE files.disk_id = ?
                ORDER BY duplicate_groups.total_size DESC
                LIMIT ?
                """,
                arguments: [diskID, limit]
            )
        }
    }

    public func duplicateGroups(limit: Int = 100) throws -> [DuplicateGroupRecord] {
        try dbQueue.read { db in
            try DuplicateGroupRecord.fetchAll(
                db,
                sql: "SELECT * FROM duplicate_groups ORDER BY total_size DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }

    public func members(forGroupID groupID: Int64) throws -> [FileRecord] {
        try dbQueue.read { db in
            try FileRecord.fetchAll(
                db,
                sql: """
                SELECT files.*
                FROM files
                JOIN duplicate_members ON duplicate_members.file_id = files.id
                WHERE duplicate_members.group_id = ?
                ORDER BY files.path ASC
                """,
                arguments: [groupID]
            )
        }
    }

    public func duplicateSavings(forDiskID diskID: Int64) throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(dg.total_size - (dg.total_size / dg.file_count)), 0)
                FROM duplicate_groups dg
                WHERE dg.file_count > 1
                  AND dg.id IN (
                    SELECT DISTINCT dm.group_id
                    FROM duplicate_members dm
                    JOIN files f ON f.id = dm.file_id
                    WHERE f.disk_id = ?
                  )
                """,
                arguments: [diskID]
            ) ?? 0
        }
    }

    public func topConsumers(forDiskID diskID: Int64, limit: Int = 10) throws -> [SpaceConsumer] {
        let files = try self.files(forDiskID: diskID, limit: 10_000)
        var buckets: [String: (size: Int64, count: Int)] = [:]

        for file in files {
            let name = Self.consumerName(for: file.path)
            var bucket = buckets[name, default: (0, 0)]
            bucket.size += file.size
            bucket.count += 1
            buckets[name] = bucket
        }

        return buckets
            .map { SpaceConsumer(name: $0.key, totalSize: $0.value.size, fileCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(limit)
            .map { $0 }
    }

    private static func consumerName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents

        if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            return components[appIndex].replacingOccurrences(of: ".app", with: "")
        }

        if let containersIndex = components.firstIndex(of: "Containers"), containersIndex + 1 < components.count {
            return components[containersIndex + 1]
        }

        if let downloadsIndex = components.firstIndex(of: "Downloads") {
            if downloadsIndex + 1 < components.count {
                return "Downloads/\(components[downloadsIndex + 1])"
            }
            return "Downloads"
        }

        if path.contains("/Library/Developer") || path.contains("/DerivedData") {
            return "Xcode"
        }
        if path.contains("/.docker") || path.contains("Docker") {
            return "Docker"
        }
        if path.contains("/Library/Application Support/Adobe") {
            return "Adobe Creative Cloud"
        }

        if components.count >= 3 {
            return components[2]
        }

        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? "Other" : parent
    }

    public func categorySize(forDiskID diskID: Int64, category: FileCategory) throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(size), 0) FROM files WHERE disk_id = ? AND category = ?",
                arguments: [diskID, category.rawValue]
            ) ?? 0
        }
    }

    public func files(
        forRecommendationType type: String,
        diskID: Int64,
        oldFileThreshold: Date,
        limit: Int = 500
    ) throws -> [FileRecord] {
        switch type {
        case "duplicate_cleanup":
            let groups = try duplicateGroups(forDiskID: diskID, limit: limit)
            var extras: [FileRecord] = []
            for group in groups {
                guard let groupID = group.id else { continue }
                let members = try members(forGroupID: groupID)
                extras.append(contentsOf: members.dropFirst())
            }
            return extras.sorted { $0.size > $1.size }

        case "delete_cache":
            return try files(inCategory: .cache, diskID: diskID, limit: limit)

        case "delete_dmg":
            return try dbQueue.read { db in
                let candidates = try FileRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM files
                    WHERE disk_id = ?
                      AND (
                        LOWER(path) LIKE '%.dmg'
                        OR LOWER(path) LIKE '%.dmg.aea'
                        OR LOWER(path) LIKE '%.trustcache'
                        OR LOWER(path) LIKE '%.integrity_catalog'
                      )
                    ORDER BY size DESC
                    LIMIT ?
                    """,
                    arguments: [diskID, max(limit * 4, 1_000)]
                )
                return candidates
                    .filter { RemovablePathRules.isUserManagedInstallerArtifact($0.path) }
                    .sorted { lhs, rhs in
                        let left = RemovablePathRules.classifyInstallerArtifact(path: lhs.path, size: lhs.size)
                        let right = RemovablePathRules.classifyInstallerArtifact(path: rhs.path, size: rhs.size)
                        return sortRank(for: left?.level) < sortRank(for: right?.level)
                            || (sortRank(for: left?.level) == sortRank(for: right?.level) && lhs.size > rhs.size)
                    }
                    .prefix(limit)
                    .map { $0 }
            }

        case "delete_ios_backups":
            return try dbQueue.read { db in
                try FileRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM files
                    WHERE disk_id = ?
                      AND (
                        LOWER(path) LIKE '%mobilesync/backup%'
                        OR LOWER(path) LIKE '%/ios backup%'
                      )
                    ORDER BY size DESC
                    LIMIT ?
                    """,
                    arguments: [diskID, limit]
                )
            }

        case "delete_previews":
            return try dbQueue.read { db in
                try FileRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM files
                    WHERE disk_id = ?
                      AND (
                        category = ?
                        OR LOWER(path) LIKE '%preview%'
                        OR LOWER(path) LIKE '%thumb%'
                        OR LOWER(path) LIKE '%.tmp'
                      )
                    ORDER BY size DESC
                    LIMIT ?
                    """,
                    arguments: [diskID, FileCategory.temporary.rawValue, limit]
                )
            }

        case "clean_downloads":
            return try files(inCategory: .downloads, diskID: diskID, limit: limit)

        case "archive_old_files":
            return try dbQueue.read { db in
                let candidates = try FileRecord.fetchAll(
                    db,
                    sql: """
                    SELECT * FROM files
                    WHERE disk_id = ?
                      AND (
                        (last_accessed IS NOT NULL AND last_accessed < ?)
                        OR (last_accessed IS NULL AND modified_at IS NOT NULL AND modified_at < ?)
                      )
                    ORDER BY size DESC
                    LIMIT ?
                    """,
                    arguments: [diskID, oldFileThreshold, oldFileThreshold, max(limit * 4, 2_000)]
                )
                return candidates
                    .filter { VideoFileRules.isArchivableOldVideo($0.path) }
                    .prefix(limit)
                    .map { $0 }
            }

        default:
            return try files(forDiskID: diskID, limit: limit)
        }
    }

    public func files(inCategory category: FileCategory, diskID: Int64, limit: Int = 500) throws -> [FileRecord] {
        try dbQueue.read { db in
            try FileRecord.fetchAll(
                db,
                sql: """
                SELECT * FROM files
                WHERE disk_id = ? AND category = ?
                ORDER BY size DESC
                LIMIT ?
                """,
                arguments: [diskID, category.rawValue, limit]
            )
        }
    }

    public func topFiles(inChartGroup groupName: String, diskID: Int64, limit: Int = 25) throws -> [FileRecord] {
        let categoryValues = FileCategory.allCases
            .filter { $0.chartGroup == groupName }
            .map(\.rawValue)
        guard !categoryValues.isEmpty else { return [] }

        let placeholders = Array(repeating: "?", count: categoryValues.count).joined(separator: ", ")
        var arguments: [DatabaseValueConvertible?] = [diskID]
        arguments.append(contentsOf: categoryValues)
        arguments.append(limit)

        return try dbQueue.read { db in
            try FileRecord.fetchAll(
                db,
                sql: """
                SELECT * FROM files
                WHERE disk_id = ? AND category IN (\(placeholders))
                ORDER BY size DESC
                LIMIT ?
                """,
                arguments: StatementArguments(arguments)
            )
        }
    }

    public func insertRecommendations(_ recommendations: [RecommendationRecord]) throws {
        try dbQueue.write { db in
            for recommendation in recommendations {
                try recommendation.insert(db)
            }
        }
    }

    public func recommendations(status: String? = nil) throws -> [RecommendationRecord] {
        try dbQueue.read { db in
            if let status {
                return try RecommendationRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM recommendations WHERE status = ? ORDER BY estimated_savings DESC",
                    arguments: [status]
                )
            }
            return try RecommendationRecord.fetchAll(
                db,
                sql: "SELECT * FROM recommendations ORDER BY estimated_savings DESC"
            )
        }
    }

    public func storageOverview(forDiskID diskID: Int64, oldFileThreshold: Date) throws -> StorageOverview {
        try dbQueue.read { db in
            let totalSize = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(size), 0) FROM files WHERE disk_id = ?",
                arguments: [diskID]
            ) ?? 0

            let fileCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM files WHERE disk_id = ?",
                arguments: [diskID]
            ) ?? 0

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT category, COALESCE(SUM(size), 0) AS total_size, COUNT(*) AS file_count
                FROM files
                WHERE disk_id = ?
                GROUP BY category
                ORDER BY total_size DESC
                """,
                arguments: [diskID]
            )

            let summaries = rows.map { row in
                CategorySummary(
                    category: FileCategory(rawValue: row["category"]) ?? .other,
                    totalSize: row["total_size"],
                    fileCount: row["file_count"]
                )
            }

            let duplicateSavings = try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(dg.total_size - (dg.total_size / dg.file_count)), 0)
                FROM duplicate_groups dg
                WHERE dg.file_count > 1
                  AND dg.id IN (
                    SELECT DISTINCT dm.group_id
                    FROM duplicate_members dm
                    JOIN files f ON f.id = dm.file_id
                    WHERE f.disk_id = ?
                  )
                """,
                arguments: [diskID]
            ) ?? 0

            let oldFileSize = try Int64.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(size), 0)
                FROM files
                WHERE disk_id = ?
                  AND (
                    (last_accessed IS NOT NULL AND last_accessed < ?)
                    OR (last_accessed IS NULL AND modified_at IS NOT NULL AND modified_at < ?)
                  )
                """,
                arguments: [diskID, oldFileThreshold, oldFileThreshold]
            ) ?? 0

            return StorageOverview(
                totalSize: totalSize,
                fileCount: fileCount,
                categorySummaries: summaries,
                duplicateSavings: duplicateSavings,
                oldFileSize: oldFileSize
            )
        }
    }
}

private func sortRank(for level: DMGSafetyLevel?) -> Int {
    switch level {
    case .safeInstaller: return 0
    case .appleDownloadArtifact: return 1
    case .cautionOSImage: return 2
    case .none: return 3
    }
}
