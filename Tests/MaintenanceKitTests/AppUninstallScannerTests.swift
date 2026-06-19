import XCTest
@testable import MaintenanceKit

final class AppUninstallScannerTests: XCTestCase {
    func testRefreshInstalledAppRemovesAppWhenBundleAndSupportFilesAreGone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applications = root.appendingPathComponent("Applications")
        let bundlePath = applications.appendingPathComponent("Ghost.app")
        try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = AppUninstallScanner(
            fileManager: .default,
            homeDirectory: root.appendingPathComponent("Home").path,
            applicationRoots: [applications.path]
        )
        guard let scanned = scanner.scan().first(where: { $0.name == "Ghost" }) else {
            return XCTFail("Expected Ghost.app to be discovered")
        }

        try FileManager.default.removeItem(at: bundlePath)

        XCTAssertNil(scanner.refreshInstalledApp(scanned))
        XCTAssertEqual(scanner.refreshInstalledApps([scanned]), [])
    }

    func testRefreshInstalledAppKeepsLeftoverSupportFilesWhenBundleIsMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("Home")
        let applications = root.appendingPathComponent("Applications")
        let bundlePath = applications.appendingPathComponent("Leftovers.app")
        let supportPath = home
            .appendingPathComponent("Library/Application Support/Leftovers")
        try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1024).write(to: supportPath.appendingPathComponent("state.db"))

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = AppUninstallScanner(
            fileManager: .default,
            homeDirectory: home.path,
            applicationRoots: [applications.path]
        )
        guard let scanned = scanner.scan().first(where: { $0.name == "Leftovers" }) else {
            return XCTFail("Expected Leftovers.app to be discovered")
        }

        try FileManager.default.removeItem(at: bundlePath)

        let refreshed = scanner.refreshInstalledApp(scanned)
        XCTAssertNotNil(refreshed)
        XCTAssertEqual(refreshed?.size, 0)
        XCTAssertFalse(refreshed?.relatedFiles.isEmpty ?? true)
    }

    func testEntriesForUninstallSkipsMissingBundleAndRelatedFiles() throws {
        let app = InstalledApp(
            name: "Missing",
            bundlePath: "/Applications/Missing.app",
            bundleID: "com.example.missing",
            size: 100,
            version: "1.0",
            relatedFiles: [
                MaintenanceEntry(
                    path: "/Users/test/Library/Caches/Missing",
                    label: "Caches",
                    detail: "/Users/test/Library/Caches/Missing",
                    size: 50,
                    category: .appSupportFiles,
                    selectedByDefault: true
                ),
            ]
        )

        let scanner = AppUninstallScanner(fileManager: .default, homeDirectory: "/Users/test")
        XCTAssertTrue(scanner.entriesForUninstall(app: app).isEmpty)
        XCTAssertTrue(scanner.entriesForUninstall(app: app, includeAppBundle: false).isEmpty)
    }
}
