#if canImport(XCTest)
import XCTest
@testable import DatabaseKit

final class ScreenshotRulesTests: XCTestCase {
    func testDetectsMacScreenshotNames() {
        XCTAssertTrue(
            ScreenshotRules.isScreenshot(path: "/Users/me/Desktop/Screenshot 2026-09-11 at 9.28.44 am.png")
        )
        XCTAssertTrue(
            ScreenshotRules.isScreenshot(path: "/Users/me/Desktop/Screen Shot 2024-01-15 at 10.30.00 AM.png")
        )
        XCTAssertTrue(
            ScreenshotRules.isScreenshot(path: "/Users/me/Pictures/Screenshots/chat.png")
        )
        XCTAssertTrue(
            ScreenshotRules.isScreenshot(path: "/Users/me/Desktop/CleanShot 2026-01-01.png")
        )
    }

    func testIgnoresRegularPhotos() {
        XCTAssertFalse(ScreenshotRules.isScreenshot(path: "/Users/me/Pictures/IMG_1049.HEIC"))
        XCTAssertFalse(ScreenshotRules.isScreenshot(path: "/Users/me/Desktop/notes.pdf"))
        XCTAssertFalse(ScreenshotRules.isScreenshot(path: "/Users/me/Desktop/movie.mp4"))
    }

    func testSubcategory() {
        XCTAssertEqual(
            ScreenshotRules.subcategory(for: "/tmp/Screenshot.png"),
            "screenshot"
        )
        XCTAssertNil(ScreenshotRules.subcategory(for: "/tmp/photo.jpg"))
    }
}

final class ImageFileRulesTests: XCTestCase {
    func testImageExtensions() {
        XCTAssertTrue(ImageFileRules.isImageFile("/tmp/a.png"))
        XCTAssertTrue(ImageFileRules.isImageFile("/tmp/a.HEIC"))
        XCTAssertFalse(ImageFileRules.isImageFile("/tmp/a.mp4"))
    }
}
#endif
