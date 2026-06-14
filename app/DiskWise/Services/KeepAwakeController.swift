import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    @Published private(set) var isActive = false

    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0

    private init() {}

    func apply(enabled: Bool) {
        if enabled {
            activate()
        } else {
            deactivate()
        }
    }

    private func activate() {
        guard !isActive else { return }

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
        isActive = false
    }
}
