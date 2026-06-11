import AppKit
import Foundation
import SwiftUI
import DatabaseKit
import DiskScannerKit
import DuplicateKit
import CleanupKit
import AIKit

enum DiskWiseFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func formatDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "—" }
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

enum ScanPhase: String, Sendable {
    case idle
    case scanning
    case findingDuplicates
    case analyzing

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .scanning: return "Step 1 of 3 · Scanning files"
        case .findingDuplicates: return "Step 2 of 3 · Finding duplicates"
        case .analyzing: return "Step 3 of 3 · Analyzing storage"
        }
    }

    var stepNumber: Int? {
        switch self {
        case .scanning: return 1
        case .findingDuplicates: return 2
        case .analyzing: return 3
        case .idle: return nil
        }
    }
}

enum DetailPane: String, CaseIterable, Identifiable {
    case overview
    case duplicates
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .duplicates: return "Duplicates"
        case .ai: return "Ask DiskWise"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .duplicates: return "doc.on.doc"
        case .ai: return "sparkles"
        }
    }
}

enum AppStatusKind {
    case ready
    case working
    case success
    case error

    var tint: Color {
        switch self {
        case .ready: return .secondary
        case .working: return .blue
        case .success: return .green
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var disks: [DiskRecord] = []
    @Published var mountedVolumes: [MountedVolume] = []
    @Published var selectedVolumePath: String?
    @Published var selectedDiskID: Int64?
    @Published var overview: StorageOverview?
    @Published var topConsumers: [SpaceConsumer] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var analysisReport: AnalysisReport?
    @Published var scanProgress: ScanProgress?
    @Published var duplicateScanProgress: DuplicateScanProgress?
    @Published var scanPhase: ScanPhase = .idle
    @Published var isScanning = false
    @Published var isFindingDuplicates = false
    @Published var isAnalyzing = false
    @Published var statusMessage = "Ready to scan"
    @Published var statusKind: AppStatusKind = .ready
    @Published var llmReport = ""
    @Published var showFullDiskAccessPrompt = false
    @Published var fullDiskAccessWizardStep: FullDiskAccessWizardStep = .needsPermission
    @Published var hasFullDiskAccess = false
    @Published var missingExternalVolumePaths: [String] = []
    @Published var selectedPane: DetailPane = .overview
    @Published var aiQuestion = ""
    @Published var aiResponses: [AIChatMessage] = []
    @Published var selectedStorageCategory: String?
    @Published var categoryDetailFiles: [FileRecord] = []
    @Published var hoveredStorageCategory: String?
    @Published var recommendationReview: RecommendationReviewState?
    @Published var showActivityLog = false
    @Published var showAbout = false
    @Published var showWhatsNewTour = false
    @Published var isStartingUp = true
    @Published var startupMessage = "Preparing DiskWise…"
    @Published var startupCompletedSteps: Set<StartupStep> = []
    @Published var startupActiveStep: StartupStep?

    let activityLog = ActivityLog.shared
    let appSettings = AppSettings.shared

    private var database: DiskWiseDatabase!
    private var permissionPollTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var duplicateTask: Task<Void, Never>?
    private var scanStartTime: Date?
    private var lastDuplicateGroupsRefreshCount = 0
    private var lastInsightsRefreshCount = 0
    private var scanEngine: ScanEngine!
    private var duplicateEngine: DuplicateEngine!
    private let cleanupEngine = CleanupEngine()
    private var aiEngine: AIAnalysisEngine!
    private let fullDiskAccessPromptKey = "diskwise.hasSeenFullDiskAccessPrompt"

    var isPostUpgradeStartup: Bool {
        appSettings.shouldShowWhatsNew
    }

    init() {
        startupTask = Task { @MainActor in
            await performStartup()
        }
    }

    private func beginStartupStep(_ step: StartupStep, message: String) {
        startupActiveStep = step
        startupMessage = message
    }

    private func completeStartupStep(_ step: StartupStep) {
        startupCompletedSteps.insert(step)
    }

    private struct CachedScanSnapshot {
        let overview: StorageOverview?
        let topConsumers: [SpaceConsumer]
        let duplicateGroups: [DuplicateGroup]
    }

    private func performStartup() async {
        isStartingUp = true
        startupCompletedSteps = []
        startupMessage = isPostUpgradeStartup
            ? "Preparing DiskWise \(AppSettings.currentAppVersion) after update…"
            : "Preparing DiskWise…"

        let databaseURL = (try? DiskWiseDatabase.defaultURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diskwise.sqlite")

        beginStartupStep(.database, message: "Opening database and applying updates…")
        await Task.yield()

        let openedDatabase: DiskWiseDatabase
        do {
            openedDatabase = try await Task.detached(priority: .userInitiated) {
                try DiskWiseDatabase(path: databaseURL)
            }.value
        } catch {
            completeStartupStep(.database)
            startupMessage = "Could not open database: \(error.localizedDescription)"
            isStartingUp = false
            setStatus(startupMessage, kind: .error)
            return
        }

        database = openedDatabase
        scanEngine = ScanEngine(database: openedDatabase)
        duplicateEngine = DuplicateEngine(database: openedDatabase)
        aiEngine = AIAnalysisEngine(database: openedDatabase)
        completeStartupStep(.database)

        beginStartupStep(.drives, message: "Discovering connected drives…")
        await Task.yield()

        let loadedDisks = (try? await Task.detached(priority: .userInitiated) {
            try openedDatabase.allDisks()
        }.value) ?? []

        disks = loadedDisks
        refreshMountedVolumes()
        if selectedVolumePath == nil {
            selectedVolumePath = mountedVolumes.first?.mountPath
        }
        if let selectedVolumePath,
           let disk = disks.first(where: { $0.mountPath == selectedVolumePath }) {
            selectedDiskID = disk.id
        } else if selectedDiskID == nil {
            selectedDiskID = disks.first?.id
            if let disk = disks.first {
                selectedVolumePath = disk.mountPath
            }
        } else {
            selectedDiskID = nil
        }

        completeStartupStep(.drives)

        beginStartupStep(.storageData, message: "Loading your saved storage scans…")
        await Task.yield()

        if let diskID = selectedDiskID {
            let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
            let snapshot = await Task.detached(priority: .userInitiated) {
                let overview = try? openedDatabase.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
                let topConsumers = (try? openedDatabase.topConsumers(forDiskID: diskID, limit: 8)) ?? []
                let duplicateEngine = DuplicateEngine(database: openedDatabase)
                let duplicateGroups = (try? duplicateEngine.loadGroups(forDiskID: diskID)) ?? []
                return CachedScanSnapshot(
                    overview: overview,
                    topConsumers: topConsumers,
                    duplicateGroups: duplicateGroups
                )
            }.value

            overview = snapshot.overview
            topConsumers = snapshot.topConsumers
            duplicateGroups = snapshot.duplicateGroups
        } else {
            overview = nil
            topConsumers = []
            duplicateGroups = []
            analysisReport = nil
        }

        completeStartupStep(.storageData)

        beginStartupStep(.permissions, message: "Checking Full Disk Access…")
        await Task.yield()

        FullDiskAccess.registerForFullDiskAccess()
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        completeStartupStep(.permissions)

        startupActiveStep = nil
        startupMessage = "Ready"
        isStartingUp = false

        presentFullDiskAccessPromptIfNeeded()
        refreshAnalysisReportInBackground()
    }

    private func refreshAnalysisReportInBackground() {
        guard selectedDiskID != nil else { return }
        Task { @MainActor in
            refreshAnalysisReport()
        }
    }

    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: fullDiskAccessPromptKey)
    }

    var shouldShowFullDiskAccessBanner: Bool {
        !showFullDiskAccessPrompt
            && !hasFullDiskAccess
            && (mountedVolumes.isEmpty || !missingExternalVolumePaths.isEmpty)
    }

    var selectedVolume: MountedVolume? {
        guard let selectedVolumePath else { return nil }
        return mountedVolumes.first { $0.mountPath == selectedVolumePath }
    }

    var internalVolumes: [MountedVolume] {
        mountedVolumes.filter(\.isInternal)
    }

    var externalVolumes: [MountedVolume] {
        mountedVolumes.filter { !$0.isInternal }
    }

    var canEjectSelectedVolume: Bool {
        selectedVolume?.isEjectable ?? false
    }

    func isVolumeBusy(_ volume: MountedVolume) -> Bool {
        (isScanning || isFindingDuplicates) && selectedVolumePath == volume.mountPath
    }

    var hasScanData: Bool {
        overview != nil
    }

    var totalDuplicateSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableSize }
    }

    var isBackgroundWorkActive: Bool {
        isFindingDuplicates || isAnalyzing
    }

    var scanEstimatedRemaining: TimeInterval? {
        if isFindingDuplicates, let progress = duplicateScanProgress {
            guard let start = scanStartTime, progress.processedCount > 20 else { return nil }
            let elapsed = Date().timeIntervalSince(start)
            let rate = Double(progress.processedCount) / elapsed
            guard rate > 0 else { return nil }
            let remaining = Double(max(0, progress.totalCount - progress.processedCount))
            return remaining / rate
        }

        guard let progress = scanProgress,
              let start = scanStartTime,
              progress.scannedCount > 100,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(start)
        let rate = Double(progress.bytesIndexed) / elapsed
        guard rate > 0 else { return nil }

        let remainingBytes = Double(max(0, volume.usedSize - progress.bytesIndexed))
        return remainingBytes / rate
    }

    var scanProgressFraction: Double {
        if isFindingDuplicates, let progress = duplicateScanProgress {
            return 0.66 + (progress.overallFraction * 0.24)
        }
        if isAnalyzing {
            return 0.94
        }
        if isScanning {
            return scanProgressFractionFromBytes
        }
        return 0
    }

    var scanProgressFractionFromBytes: Double {
        guard let progress = scanProgress,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return isScanning ? 0.08 : 0
        }
        return min(1.0, Double(progress.bytesIndexed) / Double(volume.usedSize))
    }

    var scanProgressPercent: Int {
        Int((scanProgressFraction * 100).rounded())
    }

    var scanProgressPercentLabel: String {
        "\(scanProgressPercent)%"
    }

    var duplicateProgressDetail: String? {
        guard let progress = duplicateScanProgress else { return nil }
        let step = "Step \(progress.levelIndex + 1) of \(progress.levelCount)"
        if progress.totalCount > 0 {
            return "\(step) · \(progress.level.label) · \(progress.processedCount.formatted())/\(progress.totalCount.formatted())"
        }
        return "\(step) · \(progress.level.label)"
    }

    /// Compact label for the toolbar badge while scanning.
    var toolbarStatusMessage: String {
        if isScanning, let volume = selectedVolume {
            return "Scanning \(volume.name) · \(scanProgressPercentLabel)"
        }
        if isFindingDuplicates, let detail = duplicateProgressDetail {
            return "Checking duplicates · \(detail)"
        }
        if isAnalyzing {
            return "Analyzing storage…"
        }
        return statusMessage
    }

    func diskRecord(for volume: MountedVolume) -> DiskRecord? {
        disks.first { $0.mountPath == volume.mountPath }
    }

    func isIndexed(_ volume: MountedVolume) -> Bool {
        diskRecord(for: volume) != nil
    }

    func groupedCategorySummaries(from summaries: [CategorySummary]) -> [(name: String, totalSize: Int64, fileCount: Int)] {
        var grouped: [String: (size: Int64, count: Int)] = [:]
        for summary in summaries {
            let key = summary.category.chartGroup
            var bucket = grouped[key, default: (0, 0)]
            bucket.size += summary.totalSize
            bucket.count += summary.fileCount
            grouped[key] = bucket
        }
        return grouped
            .map { (name: $0.key, totalSize: $0.value.size, fileCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    func subSummaries(forChartGroup name: String) -> [CategorySummary] {
        guard let overview else { return [] }
        return overview.categorySummaries
            .filter { $0.category.chartGroup == name }
            .sorted { $0.totalSize > $1.totalSize }
    }

    func selectStorageCategory(_ name: String?) {
        if selectedStorageCategory == name {
            clearStorageCategorySelection()
            return
        }

        selectedStorageCategory = name
        guard let name, let diskID = selectedDiskID else {
            categoryDetailFiles = []
            return
        }
        categoryDetailFiles = (try? database.topFiles(inChartGroup: name, diskID: diskID, limit: 25)) ?? []
    }

    func clearStorageCategorySelection() {
        selectedStorageCategory = nil
        categoryDetailFiles = []
    }

    private func maybeRefreshInsightsDuringScan(_ progress: ScanProgress) {
        guard isScanning, scanPhase == .scanning else { return }
        guard progress.scannedCount - lastInsightsRefreshCount >= 5_000 else { return }

        lastInsightsRefreshCount = progress.scannedCount

        if selectedDiskID == nil {
            disks = (try? database.allDisks()) ?? []
            selectedDiskID = disks.first(where: { $0.mountPath == selectedVolumePath })?.id
        }
        guard let diskID = selectedDiskID else { return }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        overview = try? database.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
    }

    func reload() {
        disks = (try? database.allDisks()) ?? []
        refreshMountedVolumes()

        if selectedVolumePath == nil {
            selectedVolumePath = mountedVolumes.first?.mountPath
        }

        if let selectedVolumePath,
           let disk = disks.first(where: { $0.mountPath == selectedVolumePath }) {
            selectedDiskID = disk.id
        } else if selectedDiskID == nil {
            selectedDiskID = disks.first?.id
            if let disk = disks.first {
                selectedVolumePath = disk.mountPath
            }
        } else {
            selectedDiskID = nil
        }

        refreshInsights()
    }

    func refreshFromError() {
        reload()
        refreshMountedVolumes()

        guard let volume = selectedVolume ?? mountedVolumes.first else {
            setStatus("Ready to scan", kind: .ready)
            return
        }

        selectedVolumePath = volume.mountPath
        scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
    }

    func refreshMountedVolumes() {
        mountedVolumes = VolumeDiscovery.mountedVolumes()
        missingExternalVolumePaths = VolumeDiscovery.unlistedExternalVolumePaths()

        if let selectedVolumePath,
           !mountedVolumes.contains(where: { $0.mountPath == selectedVolumePath }) {
            self.selectedVolumePath = mountedVolumes.first?.mountPath
        }
    }

    func presentFullDiskAccessOverlay() {
        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = true
    }

    func presentFullDiskAccessPromptIfNeeded() {
        FullDiskAccess.registerForFullDiskAccess()
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        if hasFullDiskAccess {
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
            }
            presentWhatsNewIfNeeded()
            return
        }

        guard FullDiskAccess.shouldPromptForAccess(hasSeenPrompt: !isFirstLaunch) else {
            return
        }

        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = true

        if mountedVolumes.isEmpty {
            setStatus("No drives detected — Full Disk Access required", kind: .error)
        } else if !missingExternalVolumePaths.isEmpty {
            setStatus("Some external drives are hidden — grant Full Disk Access", kind: .error)
        } else {
            setStatus("Grant Full Disk Access to scan all drives", kind: .ready)
        }
    }

    func grantFullDiskAccess() {
        fullDiskAccessWizardStep = .waiting
        showFullDiskAccessPrompt = true
        FullDiskAccess.registerForFullDiskAccess()
        FullDiskAccessSettings.open()
        setStatus("Waiting for Full Disk Access…", kind: .working)
        startPermissionPolling()
    }

    func cancelFullDiskAccessWaiting() {
        stopPermissionPolling()
        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = false
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)

        if !hasFullDiskAccess {
            if !missingExternalVolumePaths.isEmpty || mountedVolumes.isEmpty {
                setStatus("External drives may still be hidden without Full Disk Access", kind: .error)
            } else {
                setStatus("Ready to scan", kind: .ready)
            }
        }
        presentWhatsNewIfNeeded()
    }

    func dismissFullDiskAccessPrompt() {
        stopPermissionPolling()
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
        showFullDiskAccessPrompt = false
        fullDiskAccessWizardStep = .needsPermission

        if !hasFullDiskAccess {
            if !missingExternalVolumePaths.isEmpty || mountedVolumes.isEmpty {
                setStatus("External drives may still be hidden without Full Disk Access", kind: .error)
            } else {
                setStatus("Ready to scan", kind: .ready)
            }
        }
        presentWhatsNewIfNeeded()
    }

    func presentWhatsNewIfNeeded() {
        guard appSettings.shouldShowWhatsNew else { return }
        guard !showFullDiskAccessPrompt else { return }
        showWhatsNewTour = true
    }

    func finishWhatsNewTour() {
        appSettings.markCurrentReleaseSeen()
        showWhatsNewTour = false
    }

    func stopPermissionPollingIfNeeded() {
        stopPermissionPolling()
    }

    func checkPermissionOnAppActivation() {
        guard !hasFullDiskAccess else { return }

        let previouslyMissingDrives = mountedVolumes.isEmpty || !missingExternalVolumePaths.isEmpty
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        let drivesFullyVisible = !mountedVolumes.isEmpty && missingExternalVolumePaths.isEmpty
        guard hasFullDiskAccess || drivesFullyVisible else { return }

        if showFullDiskAccessPrompt || previouslyMissingDrives {
            handleFullDiskAccessGranted(startScan: true)
        }
    }

    func refreshDrivesAfterPermissionChange() {
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        if hasFullDiskAccess || (missingExternalVolumePaths.isEmpty && !mountedVolumes.isEmpty) {
            showFullDiskAccessPrompt = false
            fullDiskAccessWizardStep = .needsPermission
            setStatus("Drives refreshed — \(mountedVolumes.count) available", kind: .success)
        } else if mountedVolumes.isEmpty {
            setStatus("Still no drives detected — check Full Disk Access", kind: .error)
        } else {
            setStatus("Some external drives are still hidden", kind: .error)
        }
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                checkPermissionStatus()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
    }

    private func checkPermissionStatus() {
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        let drivesFullyVisible = !mountedVolumes.isEmpty && missingExternalVolumePaths.isEmpty
        if hasFullDiskAccess || drivesFullyVisible {
            handleFullDiskAccessGranted(startScan: true)
        }
    }

    private func handleFullDiskAccessGranted(startScan: Bool) {
        guard fullDiskAccessWizardStep != .granted else { return }

        stopPermissionPolling()
        hasFullDiskAccess = true
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
        fullDiskAccessWizardStep = .granted
        setStatus("Full Disk Access granted", kind: .success)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            showFullDiskAccessPrompt = false
            fullDiskAccessWizardStep = .needsPermission

            guard startScan else {
                setStatus("Drives refreshed — \(mountedVolumes.count) available", kind: .success)
                return
            }

            guard let volume = selectedVolume ?? mountedVolumes.first else {
                setStatus("Permission granted — select a drive to scan", kind: .success)
                return
            }

            selectVolume(volume, autoScan: true)
        }
    }

    func selectVolume(_ volume: MountedVolume, autoScan: Bool = false) {
        selectedVolumePath = volume.mountPath
        if let disk = diskRecord(for: volume) {
            selectedDiskID = disk.id
        } else {
            selectedDiskID = nil
        }
        refreshInsights()
        setStatus("Selected \(volume.name)", kind: .ready)

        if autoScan && !isIndexed(volume) && !isScanning {
            scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
        }
    }

    func scanSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive from the sidebar first", kind: .error)
            return
        }
        scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
    }

    func scanInternalDrive() {
        if let internalVolume = internalVolumes.first {
            selectedVolumePath = internalVolume.mountPath
            scanVolume(at: URL(fileURLWithPath: internalVolume.mountPath), name: internalVolume.name)
        } else if let first = mountedVolumes.first {
            selectedVolumePath = first.mountPath
            scanVolume(at: URL(fileURLWithPath: first.mountPath), name: first.name)
        }
    }

    func ejectSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive to eject", kind: .error)
            return
        }
        ejectVolume(volume)
    }

    func ejectVolume(_ volume: MountedVolume) {
        guard volume.isEjectable else {
            setStatus("\(volume.name) cannot be ejected", kind: .error)
            return
        }

        if (isScanning || isFindingDuplicates), selectedVolumePath == volume.mountPath {
            cancelScan()
        }

        setStatus("Ejecting \(volume.name)…", kind: .working)

        Task { @MainActor in
            do {
                try VolumeEject.eject(volume)
                refreshMountedVolumes()
                if selectedVolumePath == volume.mountPath {
                    selectedVolumePath = mountedVolumes.first?.mountPath
                    selectedDiskID = nil
                    overview = nil
                    topConsumers = []
                    duplicateGroups = []
                    analysisReport = nil
                }
                reload()
                setStatus("Ejected \(volume.name)", kind: .success)
            } catch {
                refreshMountedVolumes()
                setStatus("Could not eject \(volume.name): \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        cancelDuplicateDetection()
        isScanning = false
        scanPhase = .idle
        scanProgress = nil
        scanStartTime = nil
        setStatus("Scan cancelled", kind: .ready)
    }

    func cancelDuplicateDetection() {
        duplicateTask?.cancel()
        duplicateTask = nil
        isFindingDuplicates = false
        isAnalyzing = false
        duplicateScanProgress = nil
        if !isScanning {
            scanPhase = .idle
            scanStartTime = nil
        }
    }

    func refreshCachedScanResults() {
        guard let diskID = selectedDiskID else {
            overview = nil
            topConsumers = []
            duplicateGroups = []
            analysisReport = nil
            return
        }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        overview = try? database.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
        topConsumers = (try? database.topConsumers(forDiskID: diskID, limit: 8)) ?? []
        duplicateGroups = (try? duplicateEngine.loadGroups(forDiskID: diskID)) ?? []
    }

    func refreshAnalysisReport() {
        guard let diskID = selectedDiskID else {
            analysisReport = nil
            return
        }

        analysisReport = try? aiEngine.analyze(
            diskID: diskID,
            fileLimit: appSettings.analysisFileLimit
        )
    }

    func refreshInsights() {
        refreshCachedScanResults()
        refreshAnalysisReport()
    }

    func scanVolume(at url: URL, name: String? = nil) {
        scanTask?.cancel()
        cancelDuplicateDetection()
        selectedPane = .overview
        isScanning = true
        scanPhase = .scanning
        scanStartTime = Date()
        lastInsightsRefreshCount = 0
        lastDuplicateGroupsRefreshCount = 0
        clearStorageCategorySelection()
        let volumeName = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        selectedVolumePath = url.path
        setStatus("Step 1 of 3 · Scanning \(volumeName)…", kind: .working)
        logActivity(.scan, "Started filesystem scan", detail: volumeName)

        guard let scanEngine = self.scanEngine else { return }
        scanTask = Task.detached { [weak self, scanEngine] in
            guard let self else { return }
            do {
                let summary = try scanEngine.scanVolume(
                    name: volumeName,
                    mountPath: url,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.scanProgress = progress
                            self.maybeRefreshInsightsDuringScan(progress)
                            self.setStatus(
                                "Step 1 of 3 · \(progress.scannedCount.formatted()) files · \(self.scanProgressPercentLabel)",
                                kind: .working
                            )
                        }
                    },
                    isCancelled: {
                        Task.isCancelled
                    }
                )

                await MainActor.run {
                    self.finishFilesystemScan(summary: summary, volumeName: volumeName, mountPath: url.path)
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.scanPhase = .idle
                    self.scanProgress = nil
                    self.scanStartTime = nil
                    if error is CancellationError || error.localizedDescription.contains("cancelled") {
                        self.logActivity(.scan, "Scan cancelled", detail: volumeName)
                        self.setStatus("Scan cancelled", kind: .ready)
                    } else {
                        self.logActivity(.scan, "Scan failed", detail: error.localizedDescription)
                        self.setStatus("Scan failed: \(error.localizedDescription)", kind: .error)
                    }
                }
            }
        }
    }

    private func finishFilesystemScan(summary: ScanSummary, volumeName: String, mountPath: String) {
        isScanning = false
        scanPhase = .idle
        scanProgress = nil
        selectedDiskID = summary.diskID
        selectedVolumePath = mountPath
        reload()
        setStatus(
            "Storage indexed on \(volumeName) — review results while duplicates are checked in the background",
            kind: .working
        )
        logActivity(
            .scan,
            "Filesystem scan complete",
            detail: "\(summary.scannedFiles.formatted()) files indexed on \(volumeName)"
        )
        startDuplicateDetection(diskID: summary.diskID, volumeName: volumeName)
    }

    private func startDuplicateDetection(diskID: Int64, volumeName: String) {
        duplicateTask?.cancel()
        isFindingDuplicates = true
        scanPhase = .findingDuplicates
        scanStartTime = Date()
        lastDuplicateGroupsRefreshCount = 0
        let duplicateFileLimit = appSettings.duplicateScanFileLimit
        let analysisFileLimit = appSettings.analysisFileLimit
        logActivity(
            .duplicate,
            "Started duplicate detection",
            detail: "\(volumeName) · checking largest \(duplicateFileLimit.formatted()) files"
        )

        guard let duplicateEngine = self.duplicateEngine, let aiEngine = self.aiEngine else { return }
        duplicateTask = Task.detached { [weak self, duplicateEngine, aiEngine] in
            guard let self else { return }
            do {
                let duplicateSummary = try duplicateEngine.detectAll(
                    forDiskID: diskID,
                    fileLimit: duplicateFileLimit,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.duplicateScanProgress = progress
                            self.maybeRefreshDuplicateGroupsDuringScan(progress, diskID: diskID)
                            if let detail = self.duplicateProgressDetail {
                                self.setStatus("Step 2 of 3 · \(detail)", kind: .working)
                            } else {
                                self.setStatus("Step 2 of 3 · Finding duplicates on \(volumeName)…", kind: .working)
                            }
                        }
                    },
                    isCancelled: {
                        Task.isCancelled
                    }
                )

                await MainActor.run {
                    self.isFindingDuplicates = false
                    self.duplicateScanProgress = nil
                    self.scanPhase = .analyzing
                    self.isAnalyzing = true
                    self.setStatus("Step 3 of 3 · Analyzing storage on \(volumeName)…", kind: .working)
                }

                _ = try aiEngine.analyze(diskID: diskID, fileLimit: analysisFileLimit)

                await MainActor.run {
                    self.isAnalyzing = false
                    self.scanPhase = .idle
                    self.scanStartTime = nil
                    self.refreshInsights()
                    if duplicateSummary.groupsFound > 0 {
                        self.selectedPane = .duplicates
                        self.logActivity(
                            .duplicate,
                            "Duplicate detection complete",
                            detail: "\(duplicateSummary.groupsFound) groups · \(DiskWiseFormatters.bytes.string(fromByteCount: duplicateSummary.reclaimableBytes)) reclaimable"
                        )
                        self.setStatus(
                            "Found \(duplicateSummary.groupsFound) duplicate groups — open Duplicates to move extras to Trash",
                            kind: .success
                        )
                    } else {
                        self.selectedPane = .overview
                        self.logActivity(.duplicate, "Duplicate detection complete", detail: "No groups found")
                        self.setStatus("Scan complete — no duplicate groups found on this drive", kind: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFindingDuplicates = false
                    self.isAnalyzing = false
                    self.duplicateScanProgress = nil
                    self.scanPhase = .idle
                    self.scanStartTime = nil
                    if error is CancellationError || error.localizedDescription.contains("cancelled") {
                        self.logActivity(.duplicate, "Duplicate detection cancelled")
                        self.setStatus("Duplicate check cancelled — storage overview is still available", kind: .ready)
                    } else {
                        self.logActivity(.duplicate, "Duplicate detection failed", detail: error.localizedDescription)
                        self.setStatus(
                            "Duplicate check failed: \(error.localizedDescription) — storage overview is still available",
                            kind: .error
                        )
                    }
                }
            }
        }
    }

    private func maybeRefreshDuplicateGroupsDuringScan(_ progress: DuplicateScanProgress, diskID: Int64) {
        guard isFindingDuplicates else { return }
        guard progress.processedCount - lastDuplicateGroupsRefreshCount >= 250 else { return }
        lastDuplicateGroupsRefreshCount = progress.processedCount
        duplicateGroups = (try? duplicateEngine.loadGroups(forDiskID: diskID)) ?? duplicateGroups
    }

    func generateLLMReport() {
        guard let diskID = selectedDiskID else {
            setStatus("Scan a drive first to generate AI recommendations", kind: .error)
            return
        }
        isAnalyzing = true
        setStatus("Generating AI report...", kind: .working)

        Task {
            do {
                let report = try await aiEngine.requestLLMReport(for: diskID)
                await MainActor.run {
                    self.llmReport = report
                    self.isAnalyzing = false
                    self.setStatus("AI report ready", kind: .success)
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.setStatus("AI report unavailable: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    func askAI(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        aiQuestion = ""
        aiResponses.append(AIChatMessage(role: .user, text: trimmed))

        guard let report = analysisReport else {
            aiResponses.append(AIChatMessage(
                role: .assistant,
                text: "Scan a drive first so I can analyze your storage and answer questions."
            ))
            return
        }

        let answer = Self.answerQuestion(trimmed, report: report, consumers: topConsumers)
        aiResponses.append(AIChatMessage(role: .assistant, text: answer))
    }

    private static func answerQuestion(_ question: String, report: AnalysisReport, consumers: [SpaceConsumer]) -> String {
        let lower = question.lowercased()

        if lower.contains("most") || lower.contains("consuming") || lower.contains("full") {
            if let top = consumers.first {
                let categories = report.overview.categorySummaries.prefix(3)
                    .map { "\($0.category.displayName): \(DiskWiseFormatters.bytes.string(fromByteCount: $0.totalSize))" }
                    .joined(separator: ", ")
                return "Your biggest space consumer is **\(top.name)** at \(DiskWiseFormatters.bytes.string(fromByteCount: top.totalSize)). Top categories: \(categories)."
            }
        }

        if lower.contains("safely") || lower.contains("remove") || lower.contains("delete") {
            let recs = report.recommendations.prefix(4)
                .map { "• \($0.title) — save \(DiskWiseFormatters.bytes.string(fromByteCount: $0.estimatedSavings))" }
                .joined(separator: "\n")
            return "Based on your scan, these are safe starting points:\n\(recs)\n\nAlways preview before moving files to Trash."
        }

        if lower.contains("duplicate") {
            let savings = report.overview.duplicateSavings
            return savings > 0
                ? "I found \(DiskWiseFormatters.bytes.string(fromByteCount: savings)) in duplicate files. Open the Duplicates tab to review groups and clean up safely."
                : "No significant duplicate files were detected in the latest scan."
        }

        if lower.contains("video") || lower.contains("watch") {
            let mediaSize = report.overview.categorySummaries
                .filter { $0.category == .video || $0.category == .photo }
                .reduce(Int64(0)) { $0 + $1.totalSize }
            return "Media files use \(DiskWiseFormatters.bytes.string(fromByteCount: mediaSize)). Check the Overview for your largest folders and consider archiving old exports."
        }

        let reclaimable = DiskWiseFormatters.bytes.string(fromByteCount: report.potentialReclaimableSpace)
        return "You could potentially reclaim **\(reclaimable)**. Top insight: \(report.insights.first?.title ?? "Run a scan for detailed analysis."). Try asking about duplicates, caches, or what's using the most space."
    }

    func handleRecommendation(_ recommendation: RecommendationRecord) {
        reviewRecommendation(recommendation)
    }

    func reviewRecommendation(_ recommendation: RecommendationRecord) {
        guard let diskID = selectedDiskID else {
            setStatus("Scan a drive first", kind: .error)
            return
        }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let files = (try? database.files(
            forRecommendationType: recommendation.type,
            diskID: diskID,
            oldFileThreshold: threshold,
            limit: 500
        )) ?? []

        if recommendation.type == "duplicate_cleanup" && files.isEmpty {
            selectedPane = .duplicates
            setStatus("Review duplicate groups in the Duplicates tab", kind: .ready)
            return
        }

        recommendationReview = RecommendationReviewState(
            recommendation: recommendation,
            files: files,
            selectedFileIDs: defaultSelectedFileIDs(for: recommendation.type, files: files)
        )
        logActivity(
            .recommendation,
            "Opened recommendation review",
            detail: "\(recommendation.title) · \(files.count) files · \(recommendation.type)"
        )
    }

    func dismissRecommendationReview() {
        recommendationReview = nil
    }

    @discardableResult
    func executeRecommendationCleanup(files: [FileRecord], recommendation: RecommendationRecord) -> CleanupResult {
        let preview = cleanupEngine.preview(files: files, keepFirstInEachGroup: false)
        let result = executeCleanup(preview: preview, revealTrash: true)
        if result.movedCount > 0 {
            recommendationReview = nil
        }
        return result
    }

    func previewCleanup(for group: DuplicateGroup) -> CleanupPreview {
        cleanupEngine.preview(files: group.files, keepFirstInEachGroup: true)
    }

    func previewAllDuplicatesCleanup() -> CleanupPreview? {
        guard !duplicateGroups.isEmpty else { return nil }

        var items: [CleanupItem] = []
        var totalBytes: Int64 = 0
        for group in duplicateGroups {
            let preview = cleanupEngine.preview(files: group.files, keepFirstInEachGroup: true)
            items.append(contentsOf: preview.items)
            totalBytes += preview.totalBytes
        }
        guard !items.isEmpty else { return nil }
        return CleanupPreview(items: items, totalBytes: totalBytes)
    }

    func openDuplicatesPane() {
        selectedPane = .duplicates
    }

    @discardableResult
    func executeCleanup(preview: CleanupPreview, revealTrash: Bool = false) -> CleanupResult {
        let result = cleanupEngine.execute(preview: preview)
        reportCleanupResult(result)

        if result.movedCount > 0 {
            refreshInsights()
            if revealTrash {
                revealTrashedFiles(result.trashedURLs)
            }
        }

        return result
    }

    private func reportCleanupResult(_ result: CleanupResult) {
        if result.movedCount == 0 {
            if let firstFailure = result.failures.first {
                logActivity(
                    .cleanup,
                    "Cleanup moved 0 files",
                    detail: "\(firstFailure.path): \(firstFailure.reason)"
                )
                setStatus(
                    "Nothing moved to Trash — \(firstFailure.reason)",
                    kind: .error
                )
            } else {
                logActivity(.cleanup, "Cleanup moved 0 files", detail: "No eligible files selected")
                setStatus("No files were selected to move to Trash", kind: .error)
            }
            return
        }

        let movedDetail = "\(result.movedCount) files · \(DiskWiseFormatters.bytes.string(fromByteCount: result.movedBytes))"
        if result.failures.isEmpty {
            logActivity(.cleanup, "Moved files to Trash", detail: movedDetail)
            setStatus(
                "Moved \(result.movedCount) files to Trash (\(DiskWiseFormatters.bytes.string(fromByteCount: result.movedBytes)))",
                kind: .success
            )
            return
        }

        let failureDetail = result.failures
            .prefix(3)
            .map { "\($0.path): \($0.reason)" }
            .joined(separator: " | ")
        logActivity(
            .cleanup,
            "Partial cleanup",
            detail: "\(movedDetail) · failures: \(failureDetail)"
        )
        setStatus(
            "Moved \(result.movedCount) of \(result.attemptedCount) files to Trash · \(result.failures.count) could not be removed",
            kind: .error
        )
    }

    private func logActivity(_ category: ActivityCategory, _ message: String, detail: String? = nil) {
        activityLog.log(category, message, detail: detail)
    }

    private func defaultSelectedFileIDs(for recommendationType: String, files: [FileRecord]) -> Set<Int64> {
        guard recommendationType == "delete_dmg" else {
            return Set(files.compactMap(\.id))
        }

        return Set(
            files.compactMap { file -> Int64? in
                guard let id = file.id else { return nil }
                let classification = RemovablePathRules.classifyInstallerArtifact(path: file.path, size: file.size)
                return classification?.selectedByDefault == true ? id : nil
            }
        )
    }

    private func revealTrashedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func setStatus(_ message: String, kind: AppStatusKind) {
        statusMessage = message
        statusKind = kind
    }
}

struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}
