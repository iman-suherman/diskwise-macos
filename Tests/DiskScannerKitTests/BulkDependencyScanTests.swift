#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class BulkDependencyScanTests: XCTestCase {
    func testVisibleDirectoryPatterns() {
        XCTAssertTrue(DirectorySizeOnlyPatterns.matchesVisibleDirectory(named: "node_modules"))
        XCTAssertTrue(DirectorySizeOnlyPatterns.matchesVisibleDirectory(named: "vendor"))
        XCTAssertTrue(DirectorySizeOnlyPatterns.matchesVisibleDirectory(named: "DerivedData"))
        XCTAssertFalse(DirectorySizeOnlyPatterns.matchesVisibleDirectory(named: "src"))
    }

    func testShouldNotProbeHiddenBulkUnderSystemPaths() {
        let url = URL(fileURLWithPath: "/Library/Developer")
        XCTAssertFalse(DirectorySizeOnlyPatterns.shouldProbeForHiddenDirectories(at: url, mode: .fast))
        XCTAssertFalse(DirectorySizeOnlyPatterns.shouldProbeForHiddenDirectories(at: url, mode: .deep))
    }

    func testDeepScanDoesNotSummarizeNodeModules() {
        XCTAssertFalse(DirectorySizeOnlyPatterns.shouldSummarizeDirectory(named: "node_modules", mode: .deep))
    }

    func testFastDirectorySizeUsesDu() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-fast-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let nested = root.appendingPathComponent("node_modules/pkg/lib")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fileURL = nested.appendingPathComponent("index.js")
        try Data(repeating: 0xAB, count: 4096).write(to: fileURL)

        defer { try? FileManager.default.removeItem(at: root) }

        let size = FastDirectorySize.sizeOfDirectory(at: root.path)
        XCTAssertGreaterThanOrEqual(size, 4096)
    }

    func testFastScanSummarizesNodeModulesWithoutEnumeratingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-scan-\(UUID().uuidString)")
        let nodeModules = root.appendingPathComponent("node_modules/deep/nested")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)

        for index in 0..<40 {
            let fileURL = nodeModules.appendingPathComponent("file-\(index).js")
            try Data(repeating: UInt8(index), count: 1024).write(to: fileURL)
        }

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner(batchSize: 5)
        let results = try scanner.scan(mountPath: root, mode: .fast)

        let nodeModulesEntry = results.first { $0.path.hasSuffix("/node_modules") }
        XCTAssertNotNil(nodeModulesEntry)
        XCTAssertFalse(nodeModulesEntry?.isDirectory ?? true)
        XCTAssertGreaterThan(nodeModulesEntry?.size ?? 0, 40 * 1024)
        XCTAssertFalse(results.contains { $0.path.contains("/node_modules/deep/") })
    }

    func testDeepScanEnumeratesNodeModulesFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-deep-\(UUID().uuidString)")
        let nodeModules = root.appendingPathComponent("node_modules/pkg")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        let fileURL = nodeModules.appendingPathComponent("index.js")
        try Data(repeating: 0x01, count: 512).write(to: fileURL)

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .deep)

        XCTAssertTrue(results.contains { $0.path.hasSuffix("/index.js") })
    }

    func testFastScanFindsHiddenVenvWithoutEnumeratingIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-venv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let venv = root.appendingPathComponent(".venv/lib")
        try FileManager.default.createDirectory(at: venv, withIntermediateDirectories: true)
        let fileURL = venv.appendingPathComponent("site.py")
        try Data(repeating: 0xCD, count: 8192).write(to: fileURL)

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root, mode: .fast)

        let venvEntry = results.first { $0.path.hasSuffix("/.venv") }
        XCTAssertNotNil(venvEntry)
        XCTAssertGreaterThanOrEqual(venvEntry?.size ?? 0, 8192)
        XCTAssertFalse(results.contains { $0.path.contains("/.venv/lib/") })
    }

    func testPackageBundleSummarizedWithoutEnumeratingContents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-app-\(UUID().uuidString)")
        let appBundle = root.appendingPathComponent("Sample.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        let binaryURL = appBundle.appendingPathComponent("Sample")
        try Data(repeating: 0xFE, count: 8192).write(to: binaryURL)

        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = FileScanner()
        let results = try scanner.scan(mountPath: root)

        let appEntry = results.first { $0.path.hasSuffix("/Sample.app") }
        XCTAssertNotNil(appEntry)
        XCTAssertFalse(appEntry?.isDirectory ?? true)
        XCTAssertGreaterThanOrEqual(appEntry?.size ?? 0, 8192)
        XCTAssertFalse(results.contains { $0.path.contains("/Sample.app/Contents/") })
    }
}
#endif
