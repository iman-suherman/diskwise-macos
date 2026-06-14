import XCTest
@testable import DiskScannerKit
import DatabaseKit

final class VolumeFileScopeTests: XCTestCase {
    func testSystemVolumeExcludesMountedExternalPaths() {
        let internalVolume = MountedVolume(
            name: "Macintosh HD",
            mountPath: "/",
            totalSize: 1,
            freeSize: 1,
            isInternal: true,
            isRemovable: false
        )
        let external = MountedVolume(
            name: "External Storage",
            mountPath: "/Volumes/External Storage",
            totalSize: 1,
            freeSize: 1,
            isInternal: false,
            isRemovable: true
        )

        let scope = VolumeFileScope.forVolume(internalVolume, allVolumes: [internalVolume, external])

        XCTAssertTrue(scope.matches("/System/Volumes/Data/Users/demo/file.txt"))
        XCTAssertFalse(scope.matches("/System/Volumes/Data/Volumes/External Storage/movie.mp4"))
        XCTAssertFalse(scope.matches("/Volumes/External Storage/movie.mp4"))
    }

    func testExternalVolumeIncludesBothPathAliases() {
        let external = MountedVolume(
            name: "Media",
            mountPath: "/Volumes/Media",
            totalSize: 1,
            freeSize: 1,
            isInternal: false,
            isRemovable: true
        )

        let scope = VolumeFileScope.forVolume(external, allVolumes: [external])

        XCTAssertTrue(scope.matches("/Volumes/Media/movie.mp4"))
        XCTAssertTrue(scope.matches("/System/Volumes/Data/Volumes/Media/movie.mp4"))
        XCTAssertFalse(scope.matches("/System/Volumes/Data/Users/demo/file.txt"))
    }

    func testPathScopeFilterSQLIncludesAndExcludes() {
        let filter = PathScopeFilter(
            includePathPrefixes: ["/System/Volumes/Data"],
            excludePathPrefixes: ["/System/Volumes/Data/Volumes/Media/"]
        )
        let built = filter.sqlPathFilter()
        XCTAssertTrue(built.sql.contains("LIKE"))
        XCTAssertTrue(built.sql.contains("NOT"))
        XCTAssertEqual(built.arguments.count, 4)
    }
}
