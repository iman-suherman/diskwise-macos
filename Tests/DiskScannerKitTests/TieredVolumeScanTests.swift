#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class TieredVolumeScanTests: XCTestCase {
    func testTieredScanSummarizesNonUserTopLevelFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-tiered-\(UUID().uuidString)")

        let applications = root.appendingPathComponent("Applications/BigApp.app/Contents/MacOS")
        let users = root.appendingPathComponent("Users/testuser/Documents")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: users, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 4096).write(to: applications.appendingPathComponent("BigApp"))
        try Data(repeating: 0x22, count: 2048).write(to: users.appendingPathComponent("notes.txt"))

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .fast, tieredVolumeScan: true)

        let applicationsEntry = results.first { $0.path == root.appendingPathComponent("Applications").path }
        XCTAssertNotNil(applicationsEntry)
        XCTAssertGreaterThanOrEqual(applicationsEntry?.size ?? 0, 4096)
        XCTAssertFalse(results.contains { $0.path.contains("/Applications/BigApp.app/Contents/") })

        XCTAssertTrue(results.contains { $0.path.hasSuffix("/notes.txt") })
    }

    func testTieredScanDisabledForDeepMode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-tiered-deep-\(UUID().uuidString)")
        let nodeModules = root.appendingPathComponent("node_modules/pkg")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 512).write(to: nodeModules.appendingPathComponent("index.js"))

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .deep, tieredVolumeScan: true)

        XCTAssertTrue(results.contains { $0.path.hasSuffix("/index.js") })
    }

    func testUserLibraryBulkFoldersSummarizedInFastMode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-user-library-\(UUID().uuidString)")
        let caches = root.appendingPathComponent("Users/alice/Library/Caches/com.example/deep")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 8192).write(to: caches.appendingPathComponent("cache.bin"))

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .fast, tieredVolumeScan: true)

        let cachesEntry = results.first { $0.path.hasSuffix("/Library/Caches") }
        XCTAssertNotNil(cachesEntry)
        XCTAssertGreaterThanOrEqual(cachesEntry?.size ?? 0, 8192)
        XCTAssertFalse(results.contains { $0.path.contains("/Library/Caches/com.example/deep/") })
    }

    func testScanProgressIncludesVerboseFields() {
        let progress = ScanProgress(
            scannedCount: 42,
            currentPath: "/System/Volumes/Data/Library",
            bytesIndexed: 1024,
            operation: .sizingDirectory,
            detail: "Sizing Library with disk usage",
            directoriesProcessed: 2,
            directoriesTotal: 8,
            maxConcurrency: 4,
            activeConcurrency: 2,
            identifiedDirectories: ["Applications", "Library", "Users/alice/Documents"],
            activeDirectories: ["Library", "Users/alice/Documents"],
            completedDirectories: ["Applications"]
        )

        XCTAssertEqual(progress.operation, .sizingDirectory)
        XCTAssertEqual(progress.maxConcurrency, 4)
        XCTAssertEqual(progress.activeConcurrency, 2)
        XCTAssertEqual(progress.completedDirectories, ["Applications"])
    }

    func testSequentialDrillDirectoriesExpandsUserHomes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-sequential-\(UUID().uuidString)")
        let aliceDocs = root.appendingPathComponent("Users/alice/Documents")
        let bobDownloads = root.appendingPathComponent("Users/bob/Downloads")
        try FileManager.default.createDirectory(at: aliceDocs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bobDownloads, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let usersURL = root.appendingPathComponent("Users", isDirectory: true)
        let tasks = VolumeTieredScan.sequentialDrillDirectories(at: usersURL)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.contains(where: { $0.path.hasSuffix("/Users/alice/Documents") }))
        XCTAssertTrue(tasks.contains(where: { $0.path.hasSuffix("/Users/bob/Downloads") }))
    }

    func testSequentialTieredScanIndexesMultipleUserFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-sequential-scan-\(UUID().uuidString)")
        let aliceDocs = root.appendingPathComponent("Users/alice/Documents")
        let bobDocs = root.appendingPathComponent("Users/bob/Documents")
        try FileManager.default.createDirectory(at: aliceDocs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bobDocs, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 1024).write(to: aliceDocs.appendingPathComponent("a.txt"))
        try Data(repeating: 0x22, count: 2048).write(to: bobDocs.appendingPathComponent("b.txt"))

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .fast, tieredVolumeScan: true)

        XCTAssertTrue(results.contains { $0.path.hasSuffix("/a.txt") })
        XCTAssertTrue(results.contains { $0.path.hasSuffix("/b.txt") })
    }
}
#endif
