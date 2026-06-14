import Foundation

public enum MaintenanceSection: String, CaseIterable, Sendable {
    case clean
    case projects
    case system

    public var title: String {
        switch self {
        case .clean: return "Clean My Mac"
        case .projects: return "Developer Projects"
        case .system: return "System Cleanup"
        }
    }

    public var description: String {
        switch self {
        case .clean:
            return "Caches, logs, temp files, Trash, and projects."
        case .projects:
            return "node_modules, build output, and virtual envs."
        case .system:
            return "Snapshots, app removal, and optimization."
        }
    }

    public var sidebarKinds: [MaintenanceKind] {
        MaintenanceKind.allCases.filter { kind in
            guard kind.section == self else { return false }
            if self == .system {
                return kind != .systemStatus
            }
            return true
        }
    }
}

public enum MaintenanceKind: String, CaseIterable, Sendable, Identifiable {
    case appCaches
    case browserCaches
    case developerCaches
    case logs
    case tempFiles
    case trash
    case nodeModules
    case buildArtifacts
    case virtualEnvironments
    case installers
    case apfsSnapshots
    case appUninstall
    case optimize
    case systemStatus

    public var id: String { rawValue }

    public var section: MaintenanceSection {
        switch self {
        case .appCaches, .browserCaches, .developerCaches, .logs, .tempFiles, .trash, .installers:
            return .clean
        case .nodeModules, .buildArtifacts, .virtualEnvironments:
            return .clean
        case .apfsSnapshots, .appUninstall, .optimize, .systemStatus:
            return .system
        }
    }

    public static var groupedBySection: [(section: MaintenanceSection, kinds: [MaintenanceKind])] {
        MaintenanceSection.allCases.map { section in
            (section, section.sidebarKinds)
        }
    }

    /// Maps scan-only kinds to the maintenance categories they surface.
    public var scanCategories: Set<MaintenanceCategory>? {
        switch self {
        case .appCaches: return [.userAppCache]
        case .browserCaches: return [.browserCache]
        case .developerCaches: return [.developerTools]
        case .logs: return [.systemLogs]
        case .tempFiles: return [.tempFiles]
        case .trash: return [.trash]
        case .nodeModules: return [.nodeModules]
        case .buildArtifacts: return [.buildArtifacts]
        case .virtualEnvironments: return [.virtualEnv]
        case .installers: return [.installerImages]
        case .apfsSnapshots, .appUninstall, .optimize, .systemStatus:
            return nil
        }
    }

    public var title: String {
        switch self {
        case .appCaches: return "App Caches"
        case .browserCaches: return "Browser Caches"
        case .developerCaches: return "Developer Caches"
        case .logs: return "Logs"
        case .tempFiles: return "Temporary Files"
        case .trash: return "Trash"
        case .nodeModules: return "node_modules"
        case .buildArtifacts: return "Build Artifacts"
        case .virtualEnvironments: return "Virtual Environments"
        case .installers: return "Installers"
        case .apfsSnapshots: return "APFS Snapshots"
        case .appUninstall: return "Uninstall Apps"
        case .optimize: return "Optimize"
        case .systemStatus: return "System Status"
        }
    }

    public var subtitle: String {
        switch self {
        case .appCaches:
            return "User Library caches and HTTP storage"
        case .browserCaches:
            return "Safari, Chrome, Firefox, and other browser caches"
        case .developerCaches:
            return "Xcode DerivedData, npm, Docker, Homebrew, and more"
        case .logs:
            return "User logs, crash reports, and diagnostic data"
        case .tempFiles:
            return "Temporary folders and URL session caches"
        case .trash:
            return "Items already in Trash — empty to reclaim space"
        case .nodeModules:
            return "JavaScript dependencies across your projects"
        case .buildArtifacts:
            return "dist, target, .build, and other build output"
        case .virtualEnvironments:
            return "Python venv folders that can be recreated"
        case .installers:
            return "DMG, PKG, and leftover installer files"
        case .apfsSnapshots:
            return "Local Time Machine snapshots that pin deleted blocks"
        case .appUninstall:
            return "Remove apps and their support files"
        case .optimize:
            return "Refresh services and clear diagnostic data"
        case .systemStatus:
            return "CPU, memory, disk, and health score"
        }
    }

    public var icon: String {
        switch self {
        case .appCaches: return "memorychip"
        case .browserCaches: return "globe"
        case .developerCaches: return "chevron.left.forwardslash.chevron.right"
        case .logs: return "doc.text.magnifyingglass"
        case .tempFiles: return "clock.badge.exclamationmark"
        case .trash: return "trash"
        case .nodeModules: return "shippingbox.fill"
        case .buildArtifacts: return "hammer.fill"
        case .virtualEnvironments: return "leaf.fill"
        case .installers: return "shippingbox"
        case .apfsSnapshots: return "clock.arrow.circlepath"
        case .appUninstall: return "app.badge.minus.fill"
        case .optimize: return "gauge.with.dots.needle.67percent"
        case .systemStatus: return "heart.text.square.fill"
        }
    }

    public var isScanAction: Bool {
        scanCategories != nil || self == .apfsSnapshots || self == .installers
    }
}

public enum MaintenanceCategory: String, Sendable, CaseIterable {
    case userAppCache
    case browserCache
    case developerTools
    case systemLogs
    case tempFiles
    case trash
    case orphanedAppData
    case nodeModules
    case buildArtifacts
    case virtualEnv
    case installerImages
    case applicationBundle
    case appSupportFiles
    case apfsSnapshot

    public var displayName: String {
        switch self {
        case .userAppCache: return "App Caches"
        case .browserCache: return "Browser Caches"
        case .developerTools: return "Developer Tools"
        case .systemLogs: return "Logs"
        case .tempFiles: return "Temporary Files"
        case .trash: return "Trash"
        case .orphanedAppData: return "Orphaned App Data"
        case .nodeModules: return "node_modules"
        case .buildArtifacts: return "Build Artifacts"
        case .virtualEnv: return "Virtual Environments"
        case .installerImages: return "Installers"
        case .applicationBundle: return "Application"
        case .appSupportFiles: return "Support Files"
        case .apfsSnapshot: return "APFS Snapshots"
        }
    }
}

public struct MaintenanceEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let label: String
    public let detail: String
    public let size: Int64
    public let category: MaintenanceCategory
    public let selectedByDefault: Bool
    public let isRecent: Bool
    public let modifiedAt: Date?

    public init(
        id: String? = nil,
        path: String,
        label: String,
        detail: String = "",
        size: Int64,
        category: MaintenanceCategory,
        selectedByDefault: Bool = true,
        isRecent: Bool = false,
        modifiedAt: Date? = nil
    ) {
        self.id = id ?? path
        self.path = path
        self.label = label
        self.detail = detail
        self.size = size
        self.category = category
        self.selectedByDefault = selectedByDefault
        self.isRecent = isRecent
        self.modifiedAt = modifiedAt
    }
}

public struct MaintenanceCategorySummary: Sendable, Identifiable {
    public let category: MaintenanceCategory
    public let totalSize: Int64
    public let entryCount: Int

    public var id: String { category.rawValue }

    public init(category: MaintenanceCategory, totalSize: Int64, entryCount: Int) {
        self.category = category
        self.totalSize = totalSize
        self.entryCount = entryCount
    }
}

public struct MaintenanceScanResult: Sendable {
    public let kind: MaintenanceKind
    public let entries: [MaintenanceEntry]
    public let totalBytes: Int64
    public let categorySummaries: [MaintenanceCategorySummary]

    public init(kind: MaintenanceKind, entries: [MaintenanceEntry]) {
        self.kind = kind
        self.entries = entries
        self.totalBytes = entries.reduce(0) { $0 + $1.size }
        var grouped: [MaintenanceCategory: (size: Int64, count: Int)] = [:]
        for entry in entries {
            let current = grouped[entry.category] ?? (0, 0)
            grouped[entry.category] = (current.size + entry.size, current.count + 1)
        }
        self.categorySummaries = grouped
            .map { MaintenanceCategorySummary(category: $0.key, totalSize: $0.value.size, entryCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
    }
}

public struct InstalledApp: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let bundlePath: String
    public let bundleID: String?
    public let size: Int64
    public let version: String?
    public let relatedFiles: [MaintenanceEntry]

    public var totalSize: Int64 {
        size + relatedFiles.reduce(0) { $0 + $1.size }
    }

    public init(
        name: String,
        bundlePath: String,
        bundleID: String?,
        size: Int64,
        version: String?,
        relatedFiles: [MaintenanceEntry]
    ) {
        self.id = bundlePath
        self.name = name
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.size = size
        self.version = version
        self.relatedFiles = relatedFiles
    }
}

public struct OptimizationTask: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let requiresConfirmation: Bool
    public let isDestructive: Bool

    public init(id: String, title: String, detail: String, requiresConfirmation: Bool = true, isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.requiresConfirmation = requiresConfirmation
        self.isDestructive = isDestructive
    }
}

public struct OptimizationResult: Sendable {
    public let taskID: String
    public let succeeded: Bool
    public let message: String

    public init(taskID: String, succeeded: Bool, message: String) {
        self.taskID = taskID
        self.succeeded = succeeded
        self.message = message
    }
}

public struct SystemSnapshot: Sendable {
    public let hostName: String
    public let healthScore: Int
    public let cpuUsagePercent: Double
    public let loadAverage: (one: Double, five: Double, fifteen: Double)
    public let logicalCPUs: Int
    public let memoryTotal: Int64
    public let memoryUsed: Int64
    public let memoryFree: Int64
    public let diskTotal: Int64
    public let diskUsed: Int64
    public let diskFree: Int64
    public let uptime: String
    public let osVersion: String
    public let hardwareModel: String

    public var memoryUsedPercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    public var diskUsedPercent: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal) * 100
    }
}
