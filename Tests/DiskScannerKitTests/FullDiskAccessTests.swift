#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class FullDiskAccessTests: XCTestCase {
    func testHasFullDiskAccessWhenTCCDatabaseReadable() {
        let fileManager = StubFileManager(
            readablePaths: ["/Library/Application Support/com.apple.TCC/TCC.db"]
        )
        XCTAssertTrue(FullDiskAccess.hasFullDiskAccess(fileManager: fileManager))
    }

    func testHasFullDiskAccessWhenTCCDirectoryListsContents() {
        let fileManager = StubFileManager(
            readablePaths: [],
            directoryContents: [
                "/Library/Application Support/com.apple.TCC": ["TCC.db"],
            ]
        )
        XCTAssertTrue(FullDiskAccess.hasFullDiskAccess(fileManager: fileManager))
    }

    func testHasFullDiskAccessWhenProtectedPathsUnavailable() {
        let fileManager = StubFileManager(readablePaths: [], directoryContents: [:])
        XCTAssertFalse(FullDiskAccess.hasFullDiskAccess(fileManager: fileManager))
    }

    func testShouldPromptOnFirstLaunchWithoutAccess() {
        let fileManager = StubFileManager(readablePaths: [], directoryContents: [:])
        XCTAssertTrue(FullDiskAccess.shouldPromptForAccess(hasSeenPrompt: false, fileManager: fileManager))
    }

    func testShouldNotPromptWhenAccessAlreadyGranted() {
        let fileManager = StubFileManager(
            readablePaths: ["/Library/Application Support/com.apple.TCC/TCC.db"]
        )
        XCTAssertFalse(FullDiskAccess.shouldPromptForAccess(hasSeenPrompt: false, fileManager: fileManager))
    }
}

private final class StubFileManager: FileManager, @unchecked Sendable {
    private let readablePaths: Set<String>
    private let directoryContents: [String: [String]]

    init(readablePaths: [String], directoryContents: [String: [String]] = [:]) {
        self.readablePaths = Set(readablePaths)
        self.directoryContents = directoryContents
    }

    override func isReadableFile(atPath path: String) -> Bool {
        readablePaths.contains(path)
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        if let contents = directoryContents[path] {
            return contents
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    }
}
#endif
