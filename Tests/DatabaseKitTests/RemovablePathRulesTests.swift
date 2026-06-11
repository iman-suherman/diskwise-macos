#if canImport(XCTest)
import XCTest
@testable import DatabaseKit

final class RemovablePathRulesTests: XCTestCase {
    func testRejectsMobileAssetSystemDMGs() {
        XCTAssertFalse(
            RemovablePathRules.isUserManagedInstallerArtifact(
                "/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/arm64eBaseSystem.dmg"
            )
        )
    }

    func testAcceptsUserDownloadDMGs() {
        XCTAssertTrue(
            RemovablePathRules.isUserManagedInstallerArtifact("/Users/adam/Downloads/app.dmg")
        )
        XCTAssertTrue(
            RemovablePathRules.isUserManagedInstallerArtifact("/Users/adam/Desktop/os.dmg")
        )
        XCTAssertTrue(
            RemovablePathRules.isUserManagedInstallerArtifact("/Users/adam/Documents/installer.dmg")
        )
    }

    func testRejectsPrebootAndNonUserFolders() {
        XCTAssertFalse(
            RemovablePathRules.isUserManagedInstallerArtifact(
                "/System/Volumes/Preboot/Cryptexes/OS/app.dmg"
            )
        )
        XCTAssertFalse(
            RemovablePathRules.isUserManagedInstallerArtifact(
                "/Volumes/Preboot/1B5C-0B5C-B5C0-B5C0/boot.dmg"
            )
        )
        XCTAssertFalse(
            RemovablePathRules.isUserManagedInstallerArtifact("/Users/adam/Library/Caches/app.dmg")
        )
    }

    func testAcceptsAppleDownloadArtifactsInUserFolders() {
        XCTAssertTrue(
            RemovablePathRules.isUserManagedInstallerArtifact("/Users/adam/Downloads/094-56699-097.dmg.aea")
        )
        XCTAssertFalse(
            RemovablePathRules.isUserManagedInstallerArtifact(
                "/System/Library/AssetsV2/com_apple_MobileAsset/file.dmg.aea"
            )
        )
    }

    func testClassifiesOSSImagesAsCaution() {
        let classification = RemovablePathRules.classifyInstallerArtifact(
            path: "/Users/adam/Downloads/os.dmg",
            size: 7_100_000_000
        )
        XCTAssertEqual(classification?.level, .cautionOSImage)
        XCTAssertFalse(classification?.selectedByDefault ?? true)
    }

    func testClassifiesAppInstallersAsSafe() {
        let classification = RemovablePathRules.classifyInstallerArtifact(
            path: "/Users/adam/Downloads/app.dmg",
            size: 52_400_000
        )
        XCTAssertEqual(classification?.level, .safeInstaller)
        XCTAssertTrue(classification?.selectedByDefault ?? false)
    }

    func testUserAccessibleMediaRejectsSystemAssets() {
        XCTAssertFalse(
            RemovablePathRules.isUserAccessibleMedia(
                "/System/Library/AssetsV2/com_apple_MobileAsset/AssetData/adat"
            )
        )
        XCTAssertFalse(
            RemovablePathRules.isUserAccessibleMedia(
                "/System/Volumes/Preboot/Cryptexes/OS/foo.mp4"
            )
        )
    }

    func testUserAccessibleMediaAcceptsUserVideos() {
        XCTAssertTrue(
            RemovablePathRules.isUserAccessibleMedia("/Users/adam/Movies/vacation.mp4")
        )
        XCTAssertTrue(
            RemovablePathRules.isUserAccessibleMedia("/Users/adam/Downloads/clip.mov")
        )
    }
}
#endif
