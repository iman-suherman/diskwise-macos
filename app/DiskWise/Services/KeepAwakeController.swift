import Combine
import DiskScannerKit
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    @Published private(set) var isActive = false
    @Published private(set) var activeVolumePaths: Set<String> = []

    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var diskIdleAssertionID: IOPMAssertionID = 0

    private init() {}

    func apply(enabled: Bool, volumePaths: Set<String>) {
        deactivate()

        guard enabled, !volumePaths.isEmpty else {
            activeVolumePaths = []
            return
        }

        let includesExternalDisks = volumePaths.contains { !VolumeDiscovery.isSystemVolume(mountPath: $0) }
        activate(includesExternalDisks: includesExternalDisks)
        activeVolumePaths = volumePaths
    }

    private func activate(includesExternalDisks: Bool) {
        let reason = "DiskWise Keep Awake" as CFString
        var activated = true

        if systemSleepAssertionID == 0 {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &systemSleepAssertionID
            )
            if result != kIOReturnSuccess {
                systemSleepAssertionID = 0
                activated = false
            }
        }

        if displaySleepAssertionID == 0 {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displaySleepAssertionID
            )
            if result != kIOReturnSuccess {
                displaySleepAssertionID = 0
            }
        }

        if includesExternalDisks, diskIdleAssertionID == 0 {
            let diskIdleType = "PreventDiskIdle" as CFString
            let result = IOPMAssertionCreateWithName(
                diskIdleType,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &diskIdleAssertionID
            )
            if result != kIOReturnSuccess {
                diskIdleAssertionID = 0
            }
        }

        isActive = activated && systemSleepAssertionID != 0
    }

    private func deactivate() {
        if systemSleepAssertionID != 0 {
            IOPMAssertionRelease(systemSleepAssertionID)
            systemSleepAssertionID = 0
        }
        if displaySleepAssertionID != 0 {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
        }
        if diskIdleAssertionID != 0 {
            IOPMAssertionRelease(diskIdleAssertionID)
            diskIdleAssertionID = 0
        }
        isActive = false
        activeVolumePaths = []
    }
}
