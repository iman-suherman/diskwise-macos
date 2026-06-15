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

enum ProcessCategory: String, Sendable {
    case userApplication = "User Application"
    case systemService = "System Service"
    case shell = "Shell"
    case backgroundAgent = "Background Agent"
    case commandLineTool = "Command-Line Tool"
    case unknown = "Process"
}

struct ProcessDetail: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let executablePath: String?
    let bundleIdentifier: String?
    let parentPID: Int32?
    let parentName: String?
    let ownerUsername: String?
    let isRunning: Bool
    let category: ProcessCategory
    let applicationName: String?
    let roleSummary: String
    let commandLine: String?

    var id: Int32 { pid }
}

struct HealthScoreFactor: Sendable {
    let name: String
    let usagePercent: Double
    let componentScore: Int
    let weightPercent: Int
    let statusLabel: String
    let detail: String
}

struct HealthScoreLabelBand: Sendable, Identifiable {
    let label: String
    let rangeDescription: String
    let detail: String

    var id: String { label }
}

struct HealthScoreExplanation: Sendable {
    let score: Int
    let label: String
    let summary: String
    let formulaDetail: String
    let formulaSteps: [String]
    let labelBands: [HealthScoreLabelBand]
    let factors: [HealthScoreFactor]
    let recommendations: [String]
}

enum MemoryReliefResult: Sendable, Equatable {
    case relieved(freedBytes: Int64, message: String)
    case improved(message: String)
    case noMeasurableChange(message: String)
    case requiresAdmin(message: String)
    case failed(String)
}

enum ProcessTerminateResult: Sendable, Equatable {
    case terminated
    case permissionDenied
    case processNotFound
    case protectedSystemProcess
    case failed(String)
}

struct ProcessTerminateRequest: Identifiable {
    let process: ProcessDetail
    let force: Bool
    var id: Int32 { process.pid }
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

    /// Minimum CPU usage to appear in the System Status "Top CPU" list.
    static let significantCPUPercentThreshold = 1.0

    /// Minimum memory to appear in the System Status "Top Memory" list (~200 MB).
    static let significantMemoryBytesThreshold: Int64 = 200 * 1024 * 1024

    static func significantCPUProcesses(_ processes: [ProcessUsage]) -> [ProcessUsage] {
        processes.filter { $0.cpuPercent >= significantCPUPercentThreshold }
    }

    static func significantMemoryProcesses(_ processes: [ProcessUsage]) -> [ProcessUsage] {
        processes.filter { $0.memoryBytes >= significantMemoryBytesThreshold }
    }

    static func explainHealthScore(for snapshot: SystemHealthSnapshot) -> HealthScoreExplanation {
        let cpuComponent = max(0, 100 - snapshot.cpuUsagePercent)
        let memoryComponent = max(0, 100 - snapshot.memoryUsedPercent)
        let diskComponent = max(0, 100 - snapshot.diskUsedPercent)

        let factors: [HealthScoreFactor] = [
            HealthScoreFactor(
                name: "CPU",
                usagePercent: snapshot.cpuUsagePercent,
                componentScore: Int(cpuComponent.rounded()),
                weightPercent: 40,
                statusLabel: pressureLabel(for: snapshot.cpuUsagePercent),
                detail: cpuPressureDetail(
                    usagePercent: snapshot.cpuUsagePercent,
                    loadAverage: snapshot.loadAverage1,
                    processorCount: snapshot.processorCount
                )
            ),
            HealthScoreFactor(
                name: "Memory",
                usagePercent: snapshot.memoryUsedPercent,
                componentScore: Int(memoryComponent.rounded()),
                weightPercent: 35,
                statusLabel: pressureLabel(for: snapshot.memoryUsedPercent),
                detail: memoryPressureDetail(
                    usedBytes: snapshot.memoryUsedBytes,
                    physicalBytes: snapshot.physicalMemoryBytes,
                    usedPercent: snapshot.memoryUsedPercent
                )
            ),
            HealthScoreFactor(
                name: "Disk",
                usagePercent: snapshot.diskUsedPercent,
                componentScore: Int(diskComponent.rounded()),
                weightPercent: 25,
                statusLabel: pressureLabel(for: snapshot.diskUsedPercent),
                detail: diskPressureDetail(
                    usedPercent: snapshot.diskUsedPercent,
                    freeBytes: snapshot.diskFreeBytes,
                    totalBytes: snapshot.diskTotalBytes
                )
            ),
        ]

        let recommendations = healthRecommendations(
            cpuUsagePercent: snapshot.cpuUsagePercent,
            memoryUsedPercent: snapshot.memoryUsedPercent,
            diskUsedPercent: snapshot.diskUsedPercent,
            loadAverage: snapshot.loadAverage1,
            processorCount: snapshot.processorCount
        )

        let formula = healthScoreFormula(
            cpuComponent: cpuComponent,
            memoryComponent: memoryComponent,
            diskComponent: diskComponent,
            score: snapshot.healthScore
        )

        return HealthScoreExplanation(
            score: snapshot.healthScore,
            label: healthConditionLabel(for: snapshot.healthScore),
            summary: healthSummary(
                score: snapshot.healthScore,
                cpuUsagePercent: snapshot.cpuUsagePercent,
                memoryUsedPercent: snapshot.memoryUsedPercent,
                diskUsedPercent: snapshot.diskUsedPercent
            ),
            formulaDetail: formula.detail,
            formulaSteps: formula.steps,
            labelBands: healthScoreLabelBands(),
            factors: factors,
            recommendations: recommendations
        )
    }

    static func healthScoreLabelBands() -> [HealthScoreLabelBand] {
        [
            HealthScoreLabelBand(
                label: "Good",
                rangeDescription: "70–100",
                detail: "Comfortable headroom on CPU, memory, and disk for everyday work."
            ),
            HealthScoreLabelBand(
                label: "Fair",
                rangeDescription: "40–69",
                detail: "The Mac is usable, but combined usage leaves less room for heavy workloads."
            ),
            HealthScoreLabelBand(
                label: "Poor",
                rangeDescription: "0–39",
                detail: "Significant strain — expect slowdowns, fan noise, or memory pressure."
            ),
        ]
    }

    private static func healthScoreFormula(
        cpuComponent: Double,
        memoryComponent: Double,
        diskComponent: Double,
        score: Int
    ) -> (detail: String, steps: [String]) {
        let cpuPoints = cpuComponent * 0.4
        let memoryPoints = memoryComponent * 0.35
        let diskPoints = diskComponent * 0.25
        let rawTotal = cpuPoints + memoryPoints + diskPoints

        let detail =
            "Headroom per resource is 100 minus usage %. Overall score = (CPU headroom × 40%) + (Memory headroom × 35%) + (Disk headroom × 25%), rounded to the nearest whole number."

        let steps = [
            "CPU headroom: 100 − CPU usage = \(String(format: "%.0f", cpuComponent))",
            "Memory headroom: 100 − memory usage = \(String(format: "%.0f", memoryComponent))",
            "Disk headroom: 100 − disk usage = \(String(format: "%.0f", diskComponent))",
            "CPU contribution: \(String(format: "%.0f", cpuComponent)) × 0.40 = \(String(format: "%.1f", cpuPoints))",
            "Memory contribution: \(String(format: "%.0f", memoryComponent)) × 0.35 = \(String(format: "%.1f", memoryPoints))",
            "Disk contribution: \(String(format: "%.0f", diskComponent)) × 0.25 = \(String(format: "%.1f", diskPoints))",
            "Total: \(String(format: "%.1f", cpuPoints)) + \(String(format: "%.1f", memoryPoints)) + \(String(format: "%.1f", diskPoints)) = \(String(format: "%.1f", rawTotal)) → \(score)/100",
        ]

        return (detail, steps)
    }

    private static func pressureLabel(for usagePercent: Double) -> String {
        switch usagePercent {
        case ..<50:
            return "Low pressure"
        case 50..<80:
            return "Moderate pressure"
        default:
            return "High pressure"
        }
    }

    private static func healthSummary(
        score: Int,
        cpuUsagePercent: Double,
        memoryUsedPercent: Double,
        diskUsedPercent: Double
    ) -> String {
        switch score {
        case 70...:
            return "Your Mac has comfortable headroom. CPU, memory, and disk pressure are all within a healthy range for everyday work."
        case 40..<70:
            var drivers: [String] = []
            if cpuUsagePercent >= 60 { drivers.append("CPU") }
            if memoryUsedPercent >= 60 { drivers.append("memory") }
            if diskUsedPercent >= 75 { drivers.append("disk space") }
            if drivers.isEmpty {
                return "Overall health is fair. No single resource is critically stressed, but combined usage leaves less room for heavy workloads."
            }
            return "Overall health is fair, mainly because \(drivers.joined(separator: " and ")) \(drivers.count == 1 ? "is" : "are") under moderate to high pressure."
        default:
            return "Your Mac is under significant strain. One or more resources are heavily used, which can slow apps, increase fan noise, and make the system feel sluggish."
        }
    }

    private static func cpuPressureDetail(
        usagePercent: Double,
        loadAverage: Double,
        processorCount: Int
    ) -> String {
        let loadRatio = processorCount > 0 ? loadAverage / Double(processorCount) : loadAverage
        let loadNote: String
        switch loadRatio {
        case ..<0.7:
            loadNote = "Load average suggests the CPU queue is light."
        case 0.7..<1.0:
            loadNote = "Load average is approaching full utilization across cores."
        default:
            loadNote = "Load average exceeds core count, so work is waiting for CPU time."
        }
        return "System-wide CPU usage is \(String(format: "%.1f", usagePercent))%. \(loadNote) Score contribution: 40% weight on CPU headroom."
    }

    private static func memoryPressureDetail(
        usedBytes: Int64,
        physicalBytes: Int64,
        usedPercent: Double
    ) -> String {
        "About \(MenuBarFormatters.gigabytes(usedBytes)) of \(MenuBarFormatters.gigabytes(physicalBytes)) (\(String(format: "%.1f", usedPercent))%) is actively wired, active, or compressed. macOS uses spare RAM for file cache, which is normal. Score contribution: 35% weight on memory headroom."
    }

    private static func diskPressureDetail(
        usedPercent: Double,
        freeBytes: Int64,
        totalBytes: Int64
    ) -> String {
        if totalBytes <= 0 {
            return "Disk usage for the monitored volume could not be measured."
        }
        return "\(String(format: "%.1f", usedPercent))% of the system volume is used with \(MenuBarFormatters.gigabytes(freeBytes)) free. macOS needs free space for updates, swap, and temporary files. Score contribution: 25% weight on free disk space."
    }

    private static func healthRecommendations(
        cpuUsagePercent: Double,
        memoryUsedPercent: Double,
        diskUsedPercent: Double,
        loadAverage: Double,
        processorCount: Int
    ) -> [String] {
        var items: [String] = []
        if cpuUsagePercent >= 70 || (processorCount > 0 && loadAverage > Double(processorCount)) {
            items.append("Check Top CPU for sustained heavy processes, or quit apps you are not using.")
        }
        if memoryUsedPercent >= 75 {
            items.append("Close memory-heavy apps or browser tabs, or restart apps that have grown over time.")
        }
        if diskUsedPercent >= 85 {
            items.append("Free disk space on the system volume — use DiskWise scan results to find large folders safely.")
        }
        if items.isEmpty {
            items.append("No urgent action needed. Keep an eye on Top CPU and Top Memory if performance changes.")
        }
        return items
    }

    static func idleCPUMessage(for snapshot: SystemHealthSnapshot) -> String {
        let loadPerCore = snapshot.processorCount > 0
            ? snapshot.loadAverage1 / Double(snapshot.processorCount)
            : snapshot.loadAverage1
        if snapshot.cpuUsagePercent < 5 {
            return "No process is using significant CPU right now. System CPU is \(String(format: "%.1f", snapshot.cpuUsagePercent))% across \(snapshot.processorCount) cores — mostly idle. Load per core: \(String(format: "%.2f", loadPerCore))."
        }
        return "No single process exceeds \(String(format: "%.0f", significantCPUPercentThreshold))% CPU, but overall usage is \(String(format: "%.1f", snapshot.cpuUsagePercent))%. Work may be spread across many small tasks or system services."
    }

    static func idleMemoryMessage(for snapshot: SystemHealthSnapshot) -> String {
        let thresholdGB = MenuBarFormatters.gigabytes(significantMemoryBytesThreshold)
        if snapshot.memoryUsedPercent < 50 {
            return "No process holds more than \(thresholdGB). \(String(format: "%.1f", snapshot.memoryUsedPercent))% of \(MenuBarFormatters.gigabytes(snapshot.physicalMemoryBytes)) is in use — memory is comfortably distributed."
        }
        return "No process exceeds \(thresholdGB), but \(String(format: "%.1f", snapshot.memoryUsedPercent))% of memory is in use overall. macOS may be keeping file cache in RAM, which improves performance and is released when apps need it."
    }

    static func freeInactiveMemory() async -> MemoryReliefResult {
        let before = readMemoryUsage()

        if runPurgeCommand() {
            return memoryReliefResult(before: before, usedAdmin: false)
        }

        let adminApproved = await MainActor.run {
            MenuBarPopoverSession.closeActivePopover()
            return runPurgeWithAdministratorPrivileges()
        }
        if adminApproved {
            return memoryReliefResult(before: before, usedAdmin: true)
        }

        if runMemoryPressure(level: "warn") {
            return memoryReliefResult(
                before: before,
                usedAdmin: false,
                fallbackMessage: "Memory pressure was raised to encourage macOS to reclaim inactive cache."
            )
        }

        return .requiresAdmin(
            message: "DiskWise could not purge inactive memory without administrator approval. Approve the system prompt when asked, or quit heavy apps from Top Memory below."
        )
    }

    private static func memoryReliefResult(
        before: (usedBytes: Int64, usedPercent: Double),
        usedAdmin: Bool,
        fallbackMessage: String? = nil
    ) -> MemoryReliefResult {
        usleep(600_000)
        let after = readMemoryUsage()
        let freedBytes = max(0, before.usedBytes - after.usedBytes)
        let prefix = usedAdmin ? "Purged inactive memory with administrator approval." : "Purged inactive memory and disk caches."

        if freedBytes >= 64 * 1024 * 1024 {
            return .relieved(
                freedBytes: freedBytes,
                message: "\(prefix) About \(MenuBarFormatters.gigabytes(freedBytes)) became available."
            )
        }

        if after.usedPercent + 1.0 < before.usedPercent {
            return .improved(
                message: "\(prefix) Memory pressure dropped from \(String(format: "%.1f", before.usedPercent))% to \(String(format: "%.1f", after.usedPercent))%."
            )
        }

        if let fallbackMessage {
            return .noMeasurableChange(message: fallbackMessage)
        }

        return .noMeasurableChange(
            message: "\(prefix) macOS did not report a large change — file cache may already be lean, or apps are actively using RAM."
        )
    }

    private static func runPurgeCommand() -> Bool {
        runExecutable(path: "/usr/sbin/purge", arguments: [])
    }

    @MainActor
    private static func runPurgeWithAdministratorPrivileges() -> Bool {
        let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        appleScript.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    private static func runMemoryPressure(level: String) -> Bool {
        runExecutable(path: "/usr/bin/memory_pressure", arguments: ["-l", level])
    }

    private static func runExecutable(path: String, arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

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
    static func capture(volume: MountedVolume?, processLimit: Int = 5) -> SystemHealthSnapshot {
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
            readRawProcesses(limit: processLimit),
            limit: processLimit,
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

    static let poorHealthScoreThreshold = 40

    static func poorHealthMemoryCleanupSuggestions(for snapshot: SystemHealthSnapshot) -> [String] {
        var suggestions: [String] = []

        if snapshot.memoryUsedPercent >= 60 {
            suggestions.append("Free inactive memory to reclaim cached RAM")
        }

        if let topMemory = significantMemoryProcesses(snapshot.topMemoryProcesses).first {
            let size = MenuBarFormatters.compactFreeSpace(topMemory.memoryBytes)
            suggestions.append("Close or restart \(topMemory.name) (\(size))")
        }

        if snapshot.memoryUsedPercent >= 75 {
            suggestions.append("Quit unused apps and browser tabs to reduce memory pressure")
        }

        if suggestions.isEmpty {
            suggestions.append("Use Free Memory to encourage macOS to reclaim inactive cache")
        }

        return Array(suggestions.prefix(3))
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
        // -A is required on macOS; without it ps only reports the current terminal session
        // and Top CPU / Top Memory miss system-wide heavy hitters (Python scans, WindowServer, etc.).
        process.arguments = [
            "-c",
            "/bin/ps -A\(sortFlag)c -o pid=,pcpu=,rss=,comm= 2>/dev/null | /usr/bin/head -n \(lineCount)",
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

    @MainActor
    static func inspectProcess(_ usage: ProcessUsage) -> ProcessDetail {
        let pid = usage.id
        let executablePath = processExecutablePath(pid: pid)
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let bundleIdentifier = runningApp?.bundleIdentifier
        let bsdInfo = readProcessBSDInfo(pid: pid)
        let commandLine = readProcessCommandLine(pid: pid)
        let parentPID = bsdInfo?.ppid
        let parentName = parentPID.map { resolveProcessName(pid: $0, comm: "", preferRunningApplicationNames: true) }
        let applicationName = runningApp?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = classifyProcess(
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            commandLine: commandLine,
            runningApp: runningApp
        )
        let roleSummary = describeProcessRole(
            name: usage.name,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            category: category,
            parentName: parentName,
            commandLine: commandLine,
            applicationName: applicationName
        )

        return ProcessDetail(
            pid: pid,
            name: usage.name,
            cpuPercent: usage.cpuPercent,
            memoryBytes: usage.memoryBytes,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier,
            parentPID: parentPID,
            parentName: parentName,
            ownerUsername: bsdInfo?.owner,
            isRunning: kill(pid, 0) == 0 || errno != ESRCH,
            category: category,
            applicationName: applicationName,
            roleSummary: roleSummary,
            commandLine: commandLine
        )
    }

    @MainActor
    private static func classifyProcess(
        executablePath: String?,
        bundleIdentifier: String?,
        commandLine: String?,
        runningApp: NSRunningApplication?
    ) -> ProcessCategory {
        if runningApp?.activationPolicy == .regular {
            return .userApplication
        }

        if let bundleIdentifier {
            if bundleIdentifier.hasPrefix("com.apple.") {
                if bundleIdentifier.contains(".loginwindow") || bundleIdentifier.contains("WindowServer") {
                    return .systemService
                }
                if runningApp?.activationPolicy == .accessory || runningApp?.activationPolicy == .prohibited {
                    return .backgroundAgent
                }
                return .systemService
            }
            if runningApp != nil {
                return runningApp?.activationPolicy == .accessory ? .backgroundAgent : .userApplication
            }
        }

        let basename = executablePath.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
            ?? commandLine?.split(separator: " ").first.map { String($0).lowercased() }

        if let basename {
            let shells = ["zsh", "bash", "sh", "fish", "tcsh", "csh", "dash"]
            if shells.contains(basename) || basename.hasSuffix("sh") {
                return .shell
            }
            if basename == "kernel_task" || basename.hasPrefix("com.apple.") {
                return .systemService
            }
            if ["/usr/sbin/", "/sbin/", "/System/Library/"].contains(where: { executablePath?.contains($0) == true }) {
                return .systemService
            }
            if executablePath?.contains(".app/") == true {
                return .backgroundAgent
            }
            if ["/usr/bin/", "/opt/homebrew/bin/", "/usr/local/bin/"].contains(where: { executablePath?.contains($0) == true }) {
                return .commandLineTool
            }
        }

        return .unknown
    }

    @MainActor
    private static func describeProcessRole(
        name: String,
        executablePath: String?,
        bundleIdentifier: String?,
        category: ProcessCategory,
        parentName: String?,
        commandLine: String?,
        applicationName: String?
    ) -> String {
        if let bundleIdentifier,
           let known = knownBundleDescriptions[bundleIdentifier] {
            return known
        }

        let basename = executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? name

        if let known = knownProcessDescriptions[basename.lowercased()] {
            var text = known
            if let parentName, !parentName.isEmpty {
                text += " Started by \(parentName)."
            }
            return text
        }

        switch category {
        case .userApplication:
            if let applicationName, applicationName != name {
                return "\(applicationName) is a user-facing app. This process belongs to that application and handles part of its runtime — windows, networking, or background tasks."
            }
            return "\(name) is a user application process. It provides an app you interact with directly."
        case .systemService:
            if let bundleIdentifier, bundleIdentifier.hasPrefix("com.apple.") {
                return "Apple system service (\(bundleIdentifier)). It supports macOS features such as graphics, networking, indexing, or security. These processes are usually safe to leave running."
            }
            return "\(basename) is a macOS system component. It helps the operating system manage hardware, security, or shared services."
        case .shell:
            if let parentName {
                return "Interactive shell session, typically launched by \(parentName). Shells run the commands you type in Terminal or scripts started by other apps."
            }
            return "Interactive shell (\(basename)). Shells execute commands from Terminal, IDEs, or automation tools."
        case .backgroundAgent:
            if let applicationName {
                return "Background helper for \(applicationName). It may sync data, update content, or perform tasks while the main app window is closed."
            }
            if let bundleIdentifier {
                return "Background agent (\(bundleIdentifier)). It runs support tasks without a visible window."
            }
            return "\(name) runs in the background without a main window — often indexing, syncing, or maintenance."
        case .commandLineTool:
            if let commandLine, commandLine.count > basename.count + 1 {
                return "Command-line tool invoked as: \(truncatedCommandLine(commandLine)). These processes usually finish on their own or belong to a script or IDE task."
            }
            if let parentName {
                return "Command-line tool started by \(parentName). It runs a script, build, or utility without a graphical interface."
            }
            return "\(basename) is a command-line program — often a developer tool, script runner, or maintenance utility."
        case .unknown:
            if let parentName {
                return "\(name) is a running process started by \(parentName). Check the executable path and command line below to identify the owning app or script."
            }
            return "\(name) is a running process. Use the executable path, bundle ID, and command line below to identify what launched it."
        }
    }

    private static let knownProcessDescriptions: [String: String] = [
        "kernel_task": "The macOS kernel. It manages CPU scheduling, memory, and drivers. High CPU here often means disk I/O wait or hardware activity, not a user app.",
        "windowserver": "Composites and draws every window on screen. High CPU can follow many displays, animations, or misbehaving apps.",
        "launchd": "The system bootstrap process that starts and supervises other daemons and services at boot and login.",
        "syslogd": "Collects and routes system log messages from apps and the kernel.",
        "mds": "Spotlight metadata server. Indexes files for search — can use CPU after large file changes.",
        "mdworker": "Spotlight indexer worker. Temporary spikes are normal after copying or downloading files.",
        "bird": "iCloud Drive sync agent. Uploads and downloads files to keep cloud folders in sync.",
        "cloudd": "Apple cloud infrastructure daemon used by iCloud services.",
        "trustd": "Validates certificates and code signatures for secure connections.",
        "logd": "Unified logging daemon for macOS diagnostic messages.",
        "coreaudiod": "Core Audio daemon — manages sound input/output for all apps.",
        "powerd": "Power management daemon — sleep, wake, and battery policies.",
        "locationd": "Location services daemon for apps that use GPS or Wi‑Fi positioning.",
        "nsurlsessiond": "Background networking daemon for app downloads and uploads.",
        "backupd": "Time Machine backup helper.",
        "softwareupdated": "Checks for and downloads macOS and app updates.",
        "zsh": "Z shell — an interactive command interpreter used by Terminal and many developer tools.",
        "bash": "Bourne-again shell — runs commands typed in Terminal or embedded in scripts.",
        "node": "Node.js runtime — often used by JavaScript build tools, servers, or npm scripts.",
        "npm": "Node package manager — usually running a script such as build, dev, or test.",
        "python": "Python interpreter — may be running a script, IDE tool, or automation task.",
        "java": "Java runtime — often used by IDEs, build tools, or server applications.",
        "git": "Git version control — typically invoked by an IDE, GUI client, or shell script.",
    ]

    private static let knownBundleDescriptions: [String: String] = [
        "com.apple.finder": "Finder — the macOS file manager and desktop shell.",
        "com.apple.Safari": "Safari web browser and its page rendering processes.",
        "com.apple.mail": "Apple Mail — email client and sync services.",
        "com.apple.Terminal": "Terminal — provides command-line access; child shells like zsh appear when you open tabs or run commands.",
        "com.apple.dt.Xcode": "Xcode — Apple's IDE. Spawns many helper processes for builds, simulators, and indexing.",
        "com.apple.ActivityMonitor": "Activity Monitor — shows process and resource usage.",
    ]

    private static func truncatedCommandLine(_ commandLine: String, maxLength: Int = 240) -> String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    private static func readProcessCommandLine(pid: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return nil }
        return output
    }

    static func terminateProcess(pid: pid_t, force: Bool) -> ProcessTerminateResult {
        guard pid > 1 else { return .protectedSystemProcess }

        let signal = force ? SIGKILL : SIGTERM
        if kill(pid, signal) == 0 {
            return .terminated
        }

        switch errno {
        case ESRCH:
            return .processNotFound
        case EPERM:
            return .permissionDenied
        default:
            return .failed(String(cString: strerror(errno)))
        }
    }

    private static func readProcessBSDInfo(pid: pid_t) -> (ppid: Int32, owner: String?)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let owner = getpwuid(info.pbi_uid).map { String(cString: $0.pointee.pw_name) }
        return (ppid: Int32(info.pbi_ppid), owner: owner)
    }
}

@MainActor
final class SystemHealthMonitor: ObservableObject {
    static let shared = SystemHealthMonitor()

    @Published private(set) var snapshot: SystemHealthSnapshot?
    @Published private(set) var systemVolume: MountedVolume?

    private var refreshTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?
    private var detailedRefresh = false

    private init() {
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

    func refresh(processLimit: Int = 5) {
        detailedRefresh = processLimit > 5
        let volumes = VolumeDiscovery.mountedVolumes()
        systemVolume = volumes.first(where: { VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) })
            ?? volumes.first(where: \.isInternal)
        snapshot = SystemHealthMonitorCore.capture(volume: systemVolume, processLimit: processLimit)
        let settings = AppSettings.shared
        Task {
            await SystemHealthNotificationService.shared.checkSnapshot(
                snapshot,
                notificationsEnabled: settings.systemHealthNotificationsEnabled,
                settings: settings
            )
        }
    }

    func refreshDetailed() {
        refresh(processLimit: 15)
    }

    func freeUpMemory() async -> MemoryReliefResult {
        let result = await SystemHealthMonitorCore.freeInactiveMemory()
        refreshDetailed()
        return result
    }

    private func startObserving() {
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                let interval = refreshInterval(for: snapshot)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                if detailedRefresh {
                    refresh(processLimit: 15)
                } else {
                    refresh(processLimit: 5)
                }
            }
        }
    }
}
