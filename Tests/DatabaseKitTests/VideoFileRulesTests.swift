#if canImport(XCTest)
import XCTest
@testable import DatabaseKit

final class VideoFileRulesTests: XCTestCase {
    func testAcceptsKnownVideoExtensions() {
        XCTAssertTrue(VideoFileRules.isVideoFile("/Users/adam/Movies/clip.mp4"))
        XCTAssertTrue(VideoFileRules.isVideoFile("/Users/adam/Documents/POCKET 3/DJI_0049_D.MP4"))
        XCTAssertTrue(VideoFileRules.isVideoFile("/Users/adam/Downloads/sample.mov"))
    }

    func testRejectsNonVideoExtensions() {
        XCTAssertFalse(VideoFileRules.isVideoFile("/Users/adam/Documents/perth games artwork.eps"))
        XCTAssertFalse(VideoFileRules.isVideoFile("/Users/adam/Music/talk.mp3"))
        XCTAssertFalse(VideoFileRules.isVideoFile("/System/Library/AssetsV2/model.espresso.weights"))
    }

    func testArchivableOldVideoRequiresUserFolder() {
        XCTAssertTrue(
            VideoFileRules.isArchivableOldVideo("/Users/adam/Documents/clip.mp4")
        )
        XCTAssertFalse(
            VideoFileRules.isArchivableOldVideo(
                "/System/Library/AssetsV2/com_apple_MobileAsset/AssetData/rnnf"
            )
        )
    }
}
#endif
