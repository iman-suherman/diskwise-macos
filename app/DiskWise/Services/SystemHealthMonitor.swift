import AppKit
import Darwin
import DiskScannerKit
import Foundation

struct ProcessUsage: Identifiable, Sendable {
    let id: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
}

struct SystemHealthSnapshot: Sendable {
    let healthScore: Int
    let hostName: String
    let macOSVersion: String
    let macOSBuild: String
    let cpuUsagePercent: Double
    let memoryUsedPercent: Double
    let loadAverage1: Double
    let loadAverage5: Double
    let loadAverage15: Double
    let processorCount: Int
    let memoryUsedBytes: Int64
    let physicalMemoryBytes: Int64
    let diskUsedPercent: Double
    let diskFreeBytes: Int64
    let diskTotalBytes: Int64
    let uptimeSeconds: TimeInterval
    let machineModel: String
    let topCPUProcesses: [ProcessUsage]
    let topMemoryProcesses: [ProcessUsage]

    func replacingProcesses(
        topCPU: [ProcessUsage],
        topMemory: [ProcessUsage]
    ) -> SystemHealthSnapshot {
        SystemHealthSnapshot(
            healthScore: healthScore,
            hostName: hostName,
            macOSVersion: macOSVersion,
            macOSBuild: macOSBuild,
            cpuUsagePercent: cpuUsagePercent,
            memoryUsedPercent: memoryUsedPercent,
            loadAverage1: loadAverage1,
            loadAverage5: loadAverage5,
            loadAverage15: loadAverage15,
            processorCount: processorCount,
            memoryUsedBytes: memoryUsedBytes,
            physicalMemoryBytes: physicalMemoryBytes,
            diskUsedPercent: diskUsedPercent,
            diskFreeBytes: diskFreeBytes,
            diskTotalBytes: diskTotalBytes,
            uptimeSeconds: uptimeSeconds,
            machineModel: machineModel,
            topCPUProcesses: topCPU,
            topMemoryProcesses: topMemory
        )
    }
}

enum SystemHealthMonitorCore {
    private static var previousCPUTicks: (user: Double, system: Double, idle: Double, nice: Double)?

    /// Fast path for startup — score and system metrics only; process lists load later.
    static func captureLaunchQuick(volume: MountedVolume?) async -> SystemHealthSnapshot {
        await Task.detached(priority: .userInitiated) {
            captureLaunchQuickSync(volume: volume)
        }.value
    }

    private static func captureLaunchQuickSync(volume: MountedVolume?) -> SystemHealthSnapshot {
        let cpuUsage = readCPUUsagePercent(sampleIntervalMicroseconds: 40_000)
        let memory = readMemoryUsage()
        let load = readLoadAverage()
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
        let diskUsedPercent = volume.map { $0.usageFraction * 100 } ?? 0
        let diskFreeBytes = volume?.freeSize ?? 0
        let diskTotalBytes = volume?.totalSize ?? 0
        let uptime = ProcessInfo.processInfo.systemUptime

        let score = computeHealthScore(
            cpuUsagePercent: cpuUsage,
            memoryUsedPercent: memory.usedPercent,
            diskUsedPercent: diskUsedPercent
        )

        return SystemHealthSnapshot(
            healthScore: score,
            hostName: readHostName(),
            macOSVersion: formattedMacOSVersion(),
            macOSBuild: readMacOSBuild(),
            cpuUsagePercent: cpuUsage,
            memoryUsedPercent: memory.usedPercent,
            loadAverage1: load.0,
            loadAverage5: load.1,
            loadAverage15: load.2,
            processorCount: processorCount,
            memoryUsedBytes: memory.usedBytes,
            physicalMemoryBytes: physicalMemory,
            diskUsedPercent: diskUsedPercent,
            diskFreeBytes: diskFreeBytes,
            diskTotalBytes: diskTotalBytes,
            uptimeSeconds: uptime,
            machineModel: readMachineModel(),
            topCPUProcesses: [],
            topMemoryProcesses: []
        )
    }

    static func captureTopProcesses(limit: Int) async -> (byCPU: [ProcessUsage], byMemory: [ProcessUsage]) {
        let raw = await Task.detached(priority: .utility) {
            readRawProcesses(limit: limit)
        }.value

        return await MainActor.run {
            resolveProcessNames(raw, limit: limit, preferRunningApplicationNames: true)
        }
    }

    @MainActor
    static func capture(volume: MountedVolume?) -> SystemHealthSnapshot {
        let cpuUsage = readCPUUsagePercent()
        let memory = readMemoryUsage()
        let load = readLoadAverage()
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemory = Int64(ProcessInfo.processInfo.physicalMemory)
        let diskUsedPercent = volume.map { $0.usageFraction * 100 } ?? 0
        let diskFreeBytes = volume?.freeSize ?? 0
        let diskTotalBytes = volume?.totalSize ?? 0
        let uptime = ProcessInfo.processInfo.systemUptime
        let processes = resolveProcessNames(
            readRawProcesses(limit: 5),
            limit: 5,
            preferRunningApplicationNames: true
        )

        let score = computeHealthScore(
            cpuUsagePercent: cpuUsage,
            memoryUsedPercent: memory.usedPercent,
            diskUsedPercent: diskUsedPercent
        )

        return SystemHealthSnapshot(
            healthScore: score,
            hostName: readHostName(),
            macOSVersion: formattedMacOSVersion(),
            macOSBuild: readMacOSBuild(),
            cpuUsagePercent: cpuUsage,
            memoryUsedPercent: memory.usedPercent,
            loadAverage1: load.0,
            loadAverage5: load.1,
            loadAverage15: load.2,
            processorCount: processorCount,
            memoryUsedBytes: memory.usedBytes,
            physicalMemoryBytes: physicalMemory,
            diskUsedPercent: diskUsedPercent,
            diskFreeBytes: diskFreeBytes,
            diskTotalBytes: diskTotalBytes,
            uptimeSeconds: uptime,
            machineModel: readMachineModel(),
            topCPUProcesses: processes.byCPU,
            topMemoryProcesses: processes.byMemory
        )
    }

    static func computeHealthScore(
        cpuUsagePercent: Double,
        memoryUsedPercent: Double,
        diskUsedPercent: Double
    ) -> Int {
        let cpuScore = max(0, 100 - cpuUsagePercent)
        let memoryScore = max(0, 100 - memoryUsedPercent)
        let diskScore = max(0, 100 - diskUsedPercent)
        let weighted = cpuScore * 0.4 + memoryScore * 0.35 + diskScore * 0.25
        return Int(min(100, max(0, weighted.rounded())))
    }

    static func healthScoreColor(_ score: Int) -> (red: Double, green: Double, blue: Double) {
        switch score {
        case 70...:
            return (0.2, 0.78, 0.35)
        case 40..<70:
            return (1.0, 0.6, 0.1)
        default:
            return (0.95, 0.25, 0.22)
        }
    }

    static func healthConditionLabel(for score: Int) -> String {
        switch score {
        case 70...:
            return "Good"
        case 40..<70:
            return "Fair"
        default:
            return "Poor"
        }
    }

    static func healthConditionLabelWithScore(for score: Int) -> String {
        "\(healthConditionLabel(for: score)) (\(score))"
    }

    private static func readHostName() -> String {
        ProcessInfo.processInfo.hostName
    }

    private static func formattedMacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func readMacOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var build = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else { return "Unknown" }
        return String(cString: build)
    }

    private static func readMachineModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return "Mac" }
        return String(cString: model)
    }

    private static func readLoadAverage() -> (Double, Double, Double) {
        var load = [Double](repeating: 0, count: 3)
        let count = getloadavg(&load, 3)
        guard count == 3 else { return (0, 0, 0) }
        return (load[0], load[1], load[2])
    }

    private static func readMemoryUsage() -> (usedBytes: Int64, usedPercent: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * pageSize
        let wired = Int64(stats.wire_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        let percent = physical > 0 ? Double(used) / Double(physical) * 100 : 0
        return (used, percent)
    }

    private static func readCPUTicks() -> (user: Double, system: Double, idle: Double, nice: Double)? {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            user: Double(cpuInfo.cpu_ticks.0),
            system: Double(cpuInfo.cpu_ticks.1),
            idle: Double(cpuInfo.cpu_ticks.2),
            nice: Double(cpuInfo.cpu_ticks.3)
        )
    }

    private static func cpuUsagePercent(from previous: CPUTicks, to current: CPUTicks) -> Double {
        let userDelta = current.user - previous.user
        let systemDelta = current.system - previous.system
        let idleDelta = current.idle - previous.idle
        let niceDelta = current.nice - previous.nice
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        guard totalDelta > 0 else { return 0 }
        let usedDelta = userDelta + systemDelta + niceDelta
        return min(100, max(0, usedDelta / totalDelta * 100))
    }

    private typealias CPUTicks = (user: Double, system: Double, idle: Double, nice: Double)

    private static func readCPUUsagePercent(sampleIntervalMicroseconds: useconds_t = 0) -> Double {
        guard let first = readCPUTicks() else { return 0 }

        if sampleIntervalMicroseconds > 0 {
            usleep(sampleIntervalMicroseconds)
            guard let second = readCPUTicks() else { return 0 }
            return cpuUsagePercent(from: first, to: second)
        }

        defer {
            previousCPUTicks = first
        }

        guard let previous = previousCPUTicks else { return 0 }
        return cpuUsagePercent(from: previous, to: first)
    }

    /// Reads pre-sorted top rows via `ps -rc` / `ps -mc` piped to `head` (~20ms each).
    private static func readRawProcesses(limit: Int) -> [(pid: Int32, cpuPercent: Double, memoryBytes: Int64, comm: String)] {
        let lineBudget = max(limit * 2, 12)
        var cpuRaw = ""
        var memRaw = ""
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            cpuRaw = runSortedPS(sortFlag: "r", lineCount: lineBudget)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            memRaw = runSortedPS(sortFlag: "m", lineCount: lineBudget)
            group.leave()
        }

        group.wait()

        var merged: [Int32: (pid: Int32, cpuPercent: Double, memoryBytes: Int64, comm: String)] = [:]
        for entry in parsePSOutput(cpuRaw) + parsePSOutput(memRaw) {
            if let existing = merged[entry.pid] {
                merged[entry.pid] = (
                    pid: entry.pid,
                    cpuPercent: max(existing.cpuPercent, entry.cpuPercent),
                    memoryBytes: max(existing.memoryBytes, entry.memoryBytes),
                    comm: existing.comm.isEmpty ? entry.comm : existing.comm
                )
            } else {
                merged[entry.pid] = entry
            }
        }
        return Array(merged.values)
    }

    private static func runSortedPS(sortFlag: String, lineCount: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "/bin/ps -\(sortFlag)c -o pid=,pcpu=,rss=,comm= 2>/dev/null | /usr/bin/head -n \(lineCount)",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func parsePSOutput(_ output: String) -> [(pid: Int32, cpuPercent: Double, memoryBytes: Int64, comm: String)] {
        var parsed: [(pid: Int32, cpuPercent: Double, memoryBytes: Int64, comm: String)] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Int64(parts[2]) else { continue }

            let comm = parts.dropFirst(3).joined(separator: " ")
            parsed.append((pid: pid, cpuPercent: cpu, memoryBytes: rssKB * 1024, comm: comm))
        }
        return parsed
    }

    @MainActor
    private static func resolveProcessNames(
        _ raw: [(pid: Int32, cpuPercent: Double, memoryBytes: Int64, comm: String)],
        limit: Int,
        preferRunningApplicationNames: Bool
    ) -> (byCPU: [ProcessUsage], byMemory: [ProcessUsage]) {
        let parsed = raw.map { entry -> ProcessUsage in
            let name = resolveProcessName(
                pid: entry.pid,
                comm: entry.comm,
                preferRunningApplicationNames: preferRunningApplicationNames
            )
            return ProcessUsage(
                id: entry.pid,
                name: name,
                cpuPercent: entry.cpuPercent,
                memoryBytes: entry.memoryBytes
            )
        }

        let byCPU = parsed.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit).map { $0 }
        let byMemory = parsed.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit).map { $0 }
        return (Array(byCPU), Array(byMemory))
    }

    @MainActor
    private static func resolveProcessName(
        pid: Int32,
        comm: String,
        preferRunningApplicationNames: Bool
    ) -> String {
        if preferRunningApplicationNames,
           let app = NSRunningApplication(processIdentifier: pid),
           let localizedName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localizedName.isEmpty {
            return localizedName
        }

        if let path = processExecutablePath(pid: pid) {
            let name = displayNameFromExecutablePath(path)
            if !name.isEmpty {
                return name
            }
        }

        let trimmedComm = comm.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComm.isEmpty {
            return processDisplayName(trimmedComm)
        }

        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        if proc_name(pid, &buffer, UInt32(buffer.count)) == 0 {
            let procName = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            if !procName.isEmpty {
                return processDisplayName(procName)
            }
        }

        return "Process \(pid)"
    }

    private static let processPathBufferSize = 4096

    private static func processExecutablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: processPathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func displayNameFromExecutablePath(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        if let appComponent = components.last(where: { $0.hasSuffix(".app") }) {
            return String(appComponent.dropLast(4))
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Shows the end of long process names so the recognizable app name stays visible.
    static func truncatedProcessName(_ name: String, maxLength: Int = 26) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength, maxLength > 3 else { return trimmed }
        let visibleTailCount = maxLength - 3
        return "..." + trimmed.suffix(visibleTailCount)
    }

    static func processDisplayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("/") {
            let components = trimmed.split(separator: "/").map(String.init)
            if let appComponent = components.first(where: { $0.hasSuffix(".app") }) {
                return String(appComponent.dropLast(4))
            }
            return components.last ?? trimmed
        }

        if trimmed.hasSuffix(".app") {
            return String(trimmed.dropLast(4))
        }

        return trimmed
    }
}

@MainActor
final class SystemHealthMonitor: ObservableObject {
    @Published private(set) var snapshot: SystemHealthSnapshot?
    @Published private(set) var systemVolume: MountedVolume?

    private var refreshTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?

    init() {
        startObserving()
    }

    deinit {
        refreshTask?.cancel()
        enrichTask?.cancel()
    }

    func warmUpQuick(volume: MountedVolume?) async {
        systemVolume = volume
        snapshot = await SystemHealthMonitorCore.captureLaunchQuick(volume: volume)
    }

    func enrichProcessesInBackground() {
        enrichTask?.cancel()
        enrichTask = Task { @MainActor in
            let processes = await SystemHealthMonitorCore.captureTopProcesses(limit: 5)
            guard !Task.isCancelled, let current = snapshot else { return }
            snapshot = current.replacingProcesses(topCPU: processes.byCPU, topMemory: processes.byMemory)
        }
    }

    private func refreshInterval(for snapshot: SystemHealthSnapshot?) -> Duration {
        guard let snapshot else { return .seconds(30) }
        if snapshot.healthScore < 40 || snapshot.cpuUsagePercent > 85 || snapshot.memoryUsedPercent > 85 {
            return .seconds(10)
        }
        if snapshot.healthScore < 70 {
            return .seconds(20)
        }
        return .seconds(30)
    }

    func refresh() {
        let volumes = VolumeDiscovery.mountedVolumes()
        systemVolume = volumes.first(where: { VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) })
            ?? volumes.first(where: \.isInternal)
        snapshot = SystemHealthMonitorCore.capture(volume: systemVolume)
    }

    private func startObserving() {
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                let interval = refreshInterval(for: snapshot)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
    }
}
