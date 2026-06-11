#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class DiskScannerKitTests: XCTestCase {
    func testClassifierDetectsVideoAndPreview() {
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/tmp/sample.mp4"), isDirectory: false),
            .video
        )
        XCTAssertEqual(
            FileClassifier.category(
                for: URL(fileURLWithPath: "/Users/me/Documents/DJI_0049_D.MP4"),
                isDirectory: false
            ),
            .video
        )
        XCTAssertEqual(
            FileClassifier.category(
                for: URL(fileURLWithPath: "/Users/me/Documents/artwork.eps"),
                isDirectory: false
            ),
            .other
        )
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/tmp/export.partial"), isDirectory: false),
            .temporary
        )
    }

    func testClassifierUsesPathHeuristics() {
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/Users/me/Downloads/installer.dmg"), isDirectory: false),
            .downloads
        )
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/Users/me/Library/Caches/com.app/data"), isDirectory: false),
            .cache
        )
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/Users/me/Library/Containers/com.app/Data"), isDirectory: false),
            .containers
        )
        XCTAssertEqual(
            FileClassifier.category(for: URL(fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData"), isDirectory: true),
            .development
        )
    }
}
#endif
