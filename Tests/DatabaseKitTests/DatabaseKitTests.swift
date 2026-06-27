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
            FileRecord(
                diskID: diskID,
                path: "/Volumes/Media01/photo.jpg",
                size: 50,
                category: .photo,
                extensionName: "jpg"
            ),
        ])

        let mediaExtensions = try database.extensionSummaries(
            inChartGroup: "Media",
            diskID: diskID
        )
        XCTAssertEqual(mediaExtensions.count, 2)
        XCTAssertEqual(mediaExtensions.first?.extensionName, "mp4")
        XCTAssertEqual(mediaExtensions.first?.fileCount, 2)

        let mp4Files = try database.files(
            inChartGroup: "Media",
            diskID: diskID,
            extensionName: "mp4"
        )
        XCTAssertEqual(mp4Files.count, 2)
        XCTAssertTrue(mp4Files.allSatisfy { $0.extensionName == "mp4" })

        let overview = try database.storageOverview(
            forDiskID: diskID,
            oldFileThreshold: Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        )
        XCTAssertEqual(overview.totalSize, 350)
        XCTAssertEqual(overview.fileCount, 3)
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

    func testScanHistoryInsertAndFetch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diskwise-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = try DiskWiseDatabase(path: url)
        _ = try database.upsertDisk(
            DiskRecord(name: "Macintosh HD", mountPath: "/", totalSize: 1_000_000, freeSize: 500_000)
        )
        let diskID = try XCTUnwrap(try database.allDisks().first?.id)

        let snapshot = ScanHistorySnapshot(
            categorySummaries: [
                CategorySummary(category: .video, totalSize: 500, fileCount: 2),
                CategorySummary(category: .photo, totalSize: 300, fileCount: 5),
            ],
            topConsumers: [SpaceConsumer(name: "Movies", totalSize: 500, fileCount: 2)]
        )
        let json = try XCTUnwrap(ScanHistoryRecord.encodeSnapshot(snapshot))
        try database.insertScanHistory(
            ScanHistoryRecord(
                diskID: diskID,
                scanMode: "fast",
                fileCount: 7,
                indexedBytes: 800,
                freeBytes: 500_000,
                durationSeconds: 120,
                snapshotJSON: json
            )
        )

        let history = try database.scanHistory(forDiskID: diskID)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.scanMode, "fast")
        XCTAssertEqual(history.first?.decodedSnapshot()?.majorCategories.count, 2)
    }
}
#endif
