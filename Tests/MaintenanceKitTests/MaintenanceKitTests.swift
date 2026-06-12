import XCTest
@testable import MaintenanceKit

final class MaintenanceKitTests: XCTestCase {
    func testProtectedPathRulesBlocksSystemPaths() {
        XCTAssertTrue(ProtectedPathRules.isBlockedPath("/System/Library/Caches"))
        XCTAssertTrue(ProtectedPathRules.isBlockedPath("/usr/local/bin"))
        XCTAssertFalse(ProtectedPathRules.isBlockedPath("/Users/test/Library/Caches"))
    }

    func testProtectedPathRulesUserHome() {
        let home = "/Users/test"
        XCTAssertTrue(ProtectedPathRules.isUserHomePath("/Users/test/Downloads", homeDirectory: home))
        XCTAssertFalse(ProtectedPathRules.isUserHomePath("/Users/other/Downloads", homeDirectory: home))
    }

    func testDeepCleanScannerReturnsEmptyWhenNoCaches() throws {
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let scanner = DeepCleanScanner(fileManager: .default, homeDirectory: tempHome.path)
        let result = scanner.scan()
        XCTAssertEqual(result.kind, .appCaches)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testProjectPurgeScannerFindsNodeModules() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsRoot = (home as NSString).appendingPathComponent(".diskwise-test-projects")
        let projectRoot = (projectsRoot as NSString).appendingPathComponent("demo")
        let nodeModules = (projectRoot as NSString).appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(atPath: nodeModules, withIntermediateDirectories: true)
        let sampleFile = (nodeModules as NSString).appendingPathComponent("package.json")
        try Data(repeating: 0, count: 12_000_000).write(to: URL(fileURLWithPath: sampleFile))

        defer { try? FileManager.default.removeItem(atPath: projectsRoot) }

        let scanner = ProjectPurgeScanner(
            fileManager: .default,
            homeDirectory: home,
            configuration: ProjectPurgeScanner.Configuration(scanRoots: [projectRoot])
        )
        let result = scanner.scan()
        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertEqual(result.entries.first?.category, .nodeModules)
    }

    func testSystemMonitorSnapshot() {
        let monitor = SystemMonitor()
        let snapshot = monitor.snapshot()
        XCTAssertGreaterThan(snapshot.memoryTotal, 0)
        XCTAssertGreaterThanOrEqual(snapshot.healthScore, 0)
        XCTAssertLessThanOrEqual(snapshot.healthScore, 100)
    }
}
