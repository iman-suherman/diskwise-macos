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

    func testSystemVolumeDetection() {
        XCTAssertTrue(VolumeDiscovery.isSystemVolume(mountPath: "/"))
        XCTAssertFalse(VolumeDiscovery.isSystemVolume(mountPath: "/Volumes/Media01"))
    }

    func testCanEjectExcludesSystemDrive() {
        let system = MountedVolume(
            name: "Macintosh HD",
            mountPath: "/",
            totalSize: 500_000_000_000,
            freeSize: 100_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        XCTAssertFalse(VolumeDiscovery.canEject(system))
        XCTAssertFalse(system.isEjectable)
    }

    func testCanEjectAllowsExternalRemovableDrive() {
        let external = MountedVolume(
            name: "Media01",
            mountPath: "/Volumes/Media01",
            totalSize: 2_000_000_000_000,
            freeSize: 500_000_000_000,
            isInternal: false,
            isRemovable: true
        )
        XCTAssertTrue(VolumeDiscovery.canEject(external))
        XCTAssertTrue(external.isEjectable)
    }

    func testCanEjectRejectsInternalNonRemovableVolume() {
        let internalData = MountedVolume(
            name: "Macintosh HD - Data",
            mountPath: "/System/Volumes/Data",
            totalSize: 500_000_000_000,
            freeSize: 100_000_000_000,
            isInternal: true,
            isRemovable: false
        )
        XCTAssertFalse(VolumeDiscovery.canEject(internalData))
    }
}
#endif
