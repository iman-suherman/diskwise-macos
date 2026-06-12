#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class StorageGapFillTests: XCTestCase {
    func testEffectiveScanRootUsesDataVolumeForSystemMount() {
        let root = VolumeScanRoot.effectiveScanRoot(for: URL(fileURLWithPath: "/"))
        if FileManager.default.fileExists(atPath: "/System/Volumes/Data") {
            XCTAssertEqual(root.path, "/System/Volumes/Data")
        } else {
            XCTAssertEqual(root.path, "/")
        }
    }

    func testEffectiveScanRootPreservesExternalVolume() {
        let root = VolumeScanRoot.effectiveScanRoot(for: URL(fileURLWithPath: "/Volumes/Media01"))
        XCTAssertEqual(root.path, "/Volumes/Media01")
    }

    func testAppendGapsAddsUnindexedBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskwise-gap-\(UUID().uuidString)")
        let visible = root.appendingPathComponent("visible")
        let hidden = root.appendingPathComponent("hidden")
        try FileManager.default.createDirectory(at: visible, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 2048).write(to: visible.appendingPathComponent("note.txt"))
        try Data(repeating: 0x02, count: 2_097_152).write(to: hidden.appendingPathComponent("secret.bin"))

        defer { try? FileManager.default.removeItem(at: root) }

        var results: [ScannedFile] = [
            ScannedFile(
                path: visible.appendingPathComponent("note.txt").path,
                size: 2048,
                createdAt: nil,
                modifiedAt: nil,
                lastAccessed: nil,
                extensionName: "txt",
                isDirectory: false
            ),
        ]

        StorageGapFill.appendGaps(scanRoot: root, to: &results)

        let hiddenGap = results.first { $0.path == hidden.path }
        XCTAssertNotNil(hiddenGap)
        XCTAssertGreaterThanOrEqual(hiddenGap?.size ?? 0, 2_097_152)
    }
}
#endif
