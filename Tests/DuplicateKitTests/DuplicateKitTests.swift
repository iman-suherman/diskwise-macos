#if canImport(XCTest)
import XCTest
import DatabaseKit
@testable import DuplicateKit

final class DuplicateKitTests: XCTestCase {
    func testNormalizedFilenameStripsCopySuffix() {
        let detector = DuplicateDetector()
        XCTAssertEqual(
            detector.normalizedFilename("/Volumes/Media/movie (1).mp4"),
            "movie"
        )
        XCTAssertEqual(
            detector.normalizedFilename("/Volumes/Media/movie copy.mp4"),
            "movie"
        )
    }

    func testCopyRankerPrefersOriginalLookingName() {
        let original = FileRecord(
            diskID: 1,
            path: "/Volumes/Media/holiday.jpg",
            size: 2_000_000,
            category: .photo,
            extensionName: "jpg"
        )
        let copy = FileRecord(
            diskID: 1,
            path: "/Volumes/Media/holiday copy.jpg",
            size: 2_000_000,
            category: .photo,
            extensionName: "jpg"
        )
        let keep = DuplicateCopyRanker.suggestedKeep(in: [copy, original])
        XCTAssertEqual(keep?.path, original.path)
        XCTAssertGreaterThan(DuplicateCopyRanker.score(original), DuplicateCopyRanker.score(copy))
    }
}
#endif
