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
            directoriesTotal: 8
        )

        XCTAssertEqual(progress.operation, .sizingDirectory)
        XCTAssertEqual(progress.detail, "Sizing Library with disk usage")
        XCTAssertEqual(progress.directoriesProcessed, 2)
        XCTAssertEqual(progress.directoriesTotal, 8)
    }
}
#endif
