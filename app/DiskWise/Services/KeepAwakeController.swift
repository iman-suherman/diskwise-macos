import Combine
import DiskScannerKit
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    @Published private(set) var isActive = false
    @Published private(set) var activeVolumePaths: Set<String> = []

    private var diskIdleAssertionID: IOPMAssertionID = 0
    private var keepAliveTask: Task<Void, Never>?

    private init() {}

    func apply(volumePaths: Set<String>) {
        deactivate()

        guard !volumePaths.isEmpty else {
            activeVolumePaths = []
            return
        }

        activateDiskIdleAssertion()
        startKeepAliveTask(for: volumePaths)
        activeVolumePaths = volumePaths
        isActive = true
    }

    private func activateDiskIdleAssertion() {
        let reason = "DiskWise Keep Disks Awake" as CFString
        guard diskIdleAssertionID == 0 else { return }

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

    private func startKeepAliveTask(for paths: Set<String>) {
        keepAliveTask?.cancel()
        let volumePaths = paths
        keepAliveTask = Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            while !Task.isCancelled {
                for path in volumePaths {
                    guard !Task.isCancelled else { return }
                    VolumeKeepAwakePulse.pulse(mountPath: path, fileManager: fileManager)
                }
                try? await Task.sleep(for: VolumeKeepAwakePulse.interval)
            }
        }
    }

    private func deactivate() {
        keepAliveTask?.cancel()
        keepAliveTask = nil

        if diskIdleAssertionID != 0 {
            IOPMAssertionRelease(diskIdleAssertionID)
            diskIdleAssertionID = 0
        }

        isActive = false
        activeVolumePaths = []
    }
}
