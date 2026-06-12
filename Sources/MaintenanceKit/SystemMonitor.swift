import Foundation
import Darwin

public final class SystemMonitor: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func snapshot() -> SystemSnapshot {
        let memory = memoryStats()
        let disk = diskStats()
        let load = loadAverage()
        let cpuUsage = estimatedCPUUsage(loadOneMinute: load.one, logicalCPUs: ProcessInfo.processInfo.processorCount)
        let health = healthScore(
            cpuUsage: cpuUsage,
            memoryUsedPercent: memory.usedPercent,
            diskUsedPercent: disk.usedPercent
        )

        return SystemSnapshot(
            hostName: ProcessInfo.processInfo.hostName,
            healthScore: health,
            cpuUsagePercent: cpuUsage,
            loadAverage: load,
            logicalCPUs: ProcessInfo.processInfo.processorCount,
            memoryTotal: memory.total,
            memoryUsed: memory.used,
            memoryFree: memory.free,
            diskTotal: disk.total,
            diskUsed: disk.used,
            diskFree: disk.free,
            uptime: formattedUptime(ProcessInfo.processInfo.systemUptime),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModelName()
        )
    }

    private struct MemoryStats {
        let total: Int64
        let used: Int64
        let free: Int64
        let usedPercent: Double
    }

    private struct DiskStats {
        let total: Int64
        let used: Int64
        let free: Int64
        let usedPercent: Double
    }

    private func memoryStats() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            let physical = Int64(ProcessInfo.processInfo.physicalMemory)
            return MemoryStats(total: physical, used: 0, free: physical, usedPercent: 0)
        }

        let pageSize = Int64(vm_kernel_page_size)
        let free = Int64(stats.free_count + stats.inactive_count) * pageSize
        let active = Int64(stats.active_count + stats.wire_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let used = min(total, active + compressed)
        let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0

        return MemoryStats(total: total, used: used, free: free, usedPercent: usedPercent)
    }

    private func diskStats() -> DiskStats {
        let home = fileManager.homeDirectoryForCurrentUser.path
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: home) else {
            return DiskStats(total: 0, used: 0, free: 0, usedPercent: 0)
        }

        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let used = max(0, total - free)
        let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
        return DiskStats(total: total, used: used, free: free, usedPercent: usedPercent)
    }

    private func loadAverage() -> (one: Double, five: Double, fifteen: Double) {
        var load = [Double](repeating: 0, count: 3)
        let result = getloadavg(&load, 3)
        guard result == 3 else { return (0, 0, 0) }
        return (load[0], load[1], load[2])
    }

    private func estimatedCPUUsage(loadOneMinute: Double, logicalCPUs: Int) -> Double {
        guard logicalCPUs > 0 else { return 0 }
        let normalized = (loadOneMinute / Double(logicalCPUs)) * 100
        return min(100, max(0, normalized))
    }

    private func healthScore(cpuUsage: Double, memoryUsedPercent: Double, diskUsedPercent: Double) -> Int {
        let cpuPenalty = min(40, cpuUsage * 0.35)
        let memoryPenalty = min(30, memoryUsedPercent * 0.25)
        let diskPenalty = min(30, diskUsedPercent * 0.2)
        return max(0, min(100, Int(100 - cpuPenalty - memoryPenalty - diskPenalty)))
    }

    private func formattedUptime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func hardwareModelName() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
