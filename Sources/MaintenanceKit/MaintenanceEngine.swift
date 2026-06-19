import Foundation
import CleanupKit

public final class MaintenanceEngine: @unchecked Sendable {
    private let deepCleanScanner: DeepCleanScanner
    private let projectPurgeScanner: ProjectPurgeScanner
    private let installerScanner: InstallerScanner
    private let appUninstallScanner: AppUninstallScanner
    private let apfsSnapshotScanner: APFSSnapshotScanner
    private let systemMonitor: SystemMonitor
    private let systemOptimizer: SystemOptimizer
    private let cleanupEngine: CleanupEngine

    public init(
        deepCleanScanner: DeepCleanScanner = DeepCleanScanner(),
        projectPurgeScanner: ProjectPurgeScanner = ProjectPurgeScanner(),
        installerScanner: InstallerScanner = InstallerScanner(),
        appUninstallScanner: AppUninstallScanner = AppUninstallScanner(),
        apfsSnapshotScanner: APFSSnapshotScanner = APFSSnapshotScanner(),
        systemMonitor: SystemMonitor = SystemMonitor(),
        systemOptimizer: SystemOptimizer = SystemOptimizer(),
        cleanupEngine: CleanupEngine = CleanupEngine()
    ) {
        self.deepCleanScanner = deepCleanScanner
        self.projectPurgeScanner = projectPurgeScanner
        self.installerScanner = installerScanner
        self.appUninstallScanner = appUninstallScanner
        self.apfsSnapshotScanner = apfsSnapshotScanner
        self.systemMonitor = systemMonitor
        self.systemOptimizer = systemOptimizer
        self.cleanupEngine = cleanupEngine
    }

    public func scan(_ kind: MaintenanceKind, isCancelled: (@Sendable () -> Bool)? = nil) -> MaintenanceScanResult {
        switch kind {
        case .appCaches, .browserCaches, .developerCaches, .logs, .tempFiles, .trash:
            return deepCleanScanner.scan(categories: kind.scanCategories, isCancelled: isCancelled)
        case .nodeModules, .buildArtifacts, .virtualEnvironments:
            return projectPurgeScanner.scan(categories: kind.scanCategories, isCancelled: isCancelled)
        case .installers:
            return installerScanner.scan(isCancelled: isCancelled)
        case .apfsSnapshots:
            return apfsSnapshotScanner.scan()
        case .appUninstall, .optimize, .systemStatus:
            return MaintenanceScanResult(kind: kind, entries: [])
        }
    }

    public func thinAPFSSnapshots(mountPath: String = "/") -> Int {
        apfsSnapshotScanner.thinAllSnapshots(mountPath: mountPath)
    }

    public func scanInstalledApps(isCancelled: (@Sendable () -> Bool)? = nil) -> [InstalledApp] {
        appUninstallScanner.scan(isCancelled: isCancelled)
    }

    public func refreshInstalledApp(_ app: InstalledApp) -> InstalledApp? {
        appUninstallScanner.refreshInstalledApp(app)
    }

    public func refreshInstalledApps(_ apps: [InstalledApp]) -> [InstalledApp] {
        appUninstallScanner.refreshInstalledApps(apps)
    }

    public func appBundleExists(_ app: InstalledApp) -> Bool {
        appUninstallScanner.appBundleExists(app)
    }

    public func systemSnapshot() -> SystemSnapshot {
        systemMonitor.snapshot()
    }

    public func optimizationTasks() -> [OptimizationTask] {
        systemOptimizer.availableTasks()
    }

    public func runOptimization(taskID: String) -> OptimizationResult {
        systemOptimizer.run(taskID: taskID)
    }

    public func previewCleanup(entries: [MaintenanceEntry]) -> CleanupPreview {
        let items = entries.map { entry in
            CleanupItem(id: stableID(entry.path), path: entry.path, size: entry.size)
        }
        let totalBytes = items.reduce(0) { $0 + $1.size }
        return CleanupPreview(items: items, totalBytes: totalBytes)
    }

    public func executeCleanup(entries: [MaintenanceEntry]) -> CleanupResult {
        cleanupEngine.execute(preview: previewCleanup(entries: entries))
    }

    public func uninstallApp(_ app: InstalledApp, includeAppBundle: Bool = true) -> CleanupResult {
        let entries = appUninstallScanner.entriesForUninstall(app: app, includeAppBundle: includeAppBundle)
        guard !entries.isEmpty else {
            return CleanupResult(
                movedCount: 0,
                movedBytes: 0,
                trashedURLs: [],
                failures: [
                    CleanupFailure(
                        path: app.bundlePath,
                        reason: "Nothing left to remove — the app and its support files are already gone."
                    ),
                ]
            )
        }
        return executeCleanup(entries: entries)
    }

    private func stableID(_ path: String) -> Int64 {
        Int64(bitPattern: UInt64(abs(path.hashValue)))
    }
}
