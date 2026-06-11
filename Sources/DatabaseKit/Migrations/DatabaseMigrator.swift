import Foundation
import GRDB

enum DiskWiseMigrator {
    static func make() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "disks") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("mount_path", .text).notNull().unique(onConflict: .replace)
                table.column("total_size", .integer).notNull()
                table.column("free_size", .integer).notNull()
                table.column("scanned_at", .datetime)
            }

            try db.create(table: "files") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("disk_id", .integer)
                    .notNull()
                    .indexed()
                    .references("disks", onDelete: .cascade)
                table.column("path", .text).notNull().unique(onConflict: .replace)
                table.column("size", .integer).notNull().indexed()
                table.column("hash", .text).indexed()
                table.column("mime_type", .text)
                table.column("category", .text).notNull().indexed()
                table.column("subcategory", .text)
                table.column("created_at", .datetime)
                table.column("modified_at", .datetime)
                table.column("last_accessed", .datetime)
                table.column("extension_name", .text)
            }

            try db.create(table: "file_metadata") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("file_id", .integer)
                    .notNull()
                    .indexed()
                    .references("files", onDelete: .cascade)
                table.column("metadata_type", .text).notNull()
                table.column("payload_json", .text).notNull()
            }

            try db.create(table: "duplicate_groups") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("detection_level", .integer).notNull()
                table.column("fingerprint", .text).notNull().indexed()
                table.column("total_size", .integer).notNull()
                table.column("file_count", .integer).notNull()
                table.column("created_at", .datetime).notNull()
            }

            try db.create(table: "duplicate_members") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("group_id", .integer)
                    .notNull()
                    .indexed()
                    .references("duplicate_groups", onDelete: .cascade)
                table.column("file_id", .integer)
                    .notNull()
                    .indexed()
                    .references("files", onDelete: .cascade)
                table.uniqueKey(["group_id", "file_id"])
            }

            try db.create(table: "recommendations") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("type", .text).notNull()
                table.column("title", .text).notNull()
                table.column("estimated_savings", .integer).notNull()
                table.column("reason", .text).notNull()
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("created_at", .datetime).notNull()
            }
        }

        return migrator
    }
}
