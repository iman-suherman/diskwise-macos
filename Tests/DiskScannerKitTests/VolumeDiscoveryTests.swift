#if canImport(XCTest)
import XCTest
@testable import DiskScannerKit

final class VolumeDiscoveryTests: XCTestCase {
    func testMountedVolumesIncludesRootOrVolumes() throws {
        let volumes = VolumeDiscovery.mountedVolumes()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.contains { $0.mountPath == "/" || $0.mountPath.hasPrefix("/Volumes/") })
    }

    func testHiddenVolumesAreFiltered() {
        XCTAssertTrue(VolumeDiscovery.isHiddenVolume(name: "Preboot", mountPath: "/Volumes/Preboot"))
        XCTAssertTrue(VolumeDiscovery.isHiddenVolume(name: "VM", mountPath: "/Volumes/VM"))
        XCTAssertTrue(VolumeDiscovery.isHiddenVolume(name: "Update", mountPath: "/System/Volumes/Update"))
        XCTAssertTrue(VolumeDiscovery.isHiddenVolume(name: "Hardware", mountPath: "/System/Volumes/Hardware"))
        XCTAssertFalse(VolumeDiscovery.isHiddenVolume(name: "Macintosh HD", mountPath: "/"))
        XCTAssertFalse(VolumeDiscovery.isHiddenVolume(name: "Samsung T9", mountPath: "/Volumes/Samsung T9"))
    }
}
#endif
