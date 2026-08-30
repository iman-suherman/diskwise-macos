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

    func testPhysicalStorageAcceptsRootAndExternalVolumes() {
        XCTAssertTrue(VolumeDiscovery.isPhysicalStorageVolume(mountPath: "/"))
        XCTAssertTrue(VolumeDiscovery.isPhysicalStorageVolume(mountPath: "/Volumes/Media"))
        XCTAssertTrue(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/Volumes/External Storage 1",
                deviceProtocol: "USB",
                deviceModel: "Elements 25A3"
            )
        )
        XCTAssertTrue(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/",
                deviceProtocol: "Apple Fabric",
                deviceModel: "APPLE SSD AP1024Z"
            )
        )
    }

    func testPhysicalStorageRejectsNetworkVolumes() {
        XCTAssertFalse(VolumeDiscovery.isPhysicalStorageVolume(mountPath: "/Volumes/Share", isLocal: false))
        XCTAssertFalse(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/Volumes/Time Machine",
                isNetworkVolume: true
            )
        )
    }

    func testPhysicalStorageRejectsDiskImagesAndVirtualMounts() {
        XCTAssertFalse(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/Volumes/Installer",
                deviceProtocol: "Disk Image",
                deviceModel: "Disk Image"
            )
        )
        XCTAssertFalse(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/Volumes/Simulator",
                deviceProtocol: "Virtual Interface",
                deviceModel: "Disk Image"
            )
        )
        XCTAssertFalse(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/Library/Developer/CoreSimulator/Volumes/iOS_23F77"
            )
        )
        XCTAssertFalse(
            VolumeDiscovery.isPhysicalStorageVolume(
                mountPath: "/private/var/run/com.apple.security.cryptexd/mnt/tool"
            )
        )
    }

    func testMountedVolumesExcludesLogicalDiskImages() throws {
        let volumes = VolumeDiscovery.mountedVolumes()
        XCTAssertFalse(volumes.contains { $0.mountPath.contains("CoreSimulator") })
        XCTAssertFalse(volumes.contains { $0.mountPath.contains("cryptexd") })
        for volume in volumes {
            XCTAssertTrue(
                VolumeDiscovery.isPhysicalStorageVolume(mountPath: volume.mountPath),
                "Unexpected non-physical volume in discovery: \(volume.mountPath)"
            )
        }
    }
}
#endif
