#if canImport(XCTest)
import XCTest
@testable import DatabaseKit

final class DatabaseKitTests: XCTestCase {
    func testMigrationsAndStorageOverview() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diskwise-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try DiskWiseDatabase(path: url)
        _ = try database.upsertDisk(
            DiskRecord(name: "Media01", mountPath: "/Volumes/Media01", totalSize: 1_000, freeSize: 500)
        )
        let disks = try database.allDisks()
        guard let diskID = disks.first?.id else {
            XCTFail("Expected disk id")
            return
        }

        let oldDate = Calendar.current.date(byAdding: .year, value: -3, to: Date())!
        try database.insertFiles([
            FileRecord(
                diskID: diskID,
                path: "/Volumes/Media01/a.mp4",
                size: 100,
                category: .video,
                modifiedAt: oldDate,
                lastAccessed: oldDate,
                extensionName: "mp4"
            ),
            FileRecord(
                diskID: diskID,
                path: "/Volumes/Media01/b.mp4",
                size: 200,
                category: .video,
                extensionName: "mp4"
            ),
        ])

        let overview = try database.storageOverview(
            forDiskID: diskID,
            oldFileThreshold: Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        )
        XCTAssertEqual(overview.totalSize, 300)
        XCTAssertEqual(overview.fileCount, 2)
        XCTAssertEqual(overview.oldFileSize, 100)
    }

    func testFilesWithDuplicateSizesOnlyReturnsCollisions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diskwise-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try DiskWiseDatabase(path: url)
        _ = try database.upsertDisk(
            DiskRecord(name: "Media01", mountPath: "/Volumes/Media01", totalSize: 1_000, freeSize: 500)
        )
        let diskID = try XCTUnwrap(try database.allDisks().first?.id)

        try database.insertFiles([
            FileRecord(diskID: diskID, path: "/Volumes/Media01/a.mp4", size: 100, category: .video),
            FileRecord(diskID: diskID, path: "/Volumes/Media01/b.mp4", size: 100, category: .video),
            FileRecord(diskID: diskID, path: "/Volumes/Media01/c.mp4", size: 200, category: .video),
            FileRecord(diskID: diskID, path: "/Volumes/Media01/d.mp4", size: 300, category: .video),
        ])

        let candidates = try database.filesWithDuplicateSizes(forDiskID: diskID, limit: 10)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.size == 100 })

        let videos = try database.videosWithDuplicateSizes(forDiskID: diskID, limit: 10)
        XCTAssertEqual(videos.count, 2)
    }
}
#endif
