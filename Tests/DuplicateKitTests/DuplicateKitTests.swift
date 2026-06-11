#if canImport(XCTest)
import XCTest
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
}
#endif
