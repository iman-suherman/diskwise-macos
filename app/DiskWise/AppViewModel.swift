import AppKit
import Foundation
import SwiftUI
import DatabaseKit
import DiskScannerKit
import DuplicateKit
import CleanupKit
import AIKit
import MaintenanceKit

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
    case identifying
    case analyzing

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .identifying: return "Phase 1 of 3 · Identifying disk usage"
        case .analyzing: return "Phase 2 of 3 · Analyzing storage"
        }
    }

    var stepNumber: Int? {
        switch self {
        case .identifying: return 1
        case .analyzing: return 2
        case .idle: return nil
        }
    }

    var completionLabel: String {
        "Phase 3 of 3 · Action plan ready"
    }
}

enum DetailPane: String, CaseIterable, Identifiable {
    case overview
    case maintenance
    case duplicates
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .maintenance: return "Maintenance"
        case .duplicates: return "Duplicates"
        case .ai: return "Ask DiskWise"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .maintenance: return "wrench.and.screwdriver.fill"
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
    private(set) static weak var current: AppViewModel?

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
    @Published var aiProviderStatus: AIProviderStatus = .unavailable
    @Published var aiSuggestedQuestions: [String] = []
    @Published var aiAutocompleteSuggestions: [String] = []
    @Published var aiAnalysisSummary = ""
    @Published var isAITyping = false
    @Published var selectedStorageCategory: String?
    @Published var categoryDetailFiles: [FileRecord] = []
    @Published var hoveredStorageCategory: String?
    @Published var recommendationReview: RecommendationReviewState?
    @Published var showActivityLog = false
    @Published var showAbout = false
    @Published var showWhatsNewTour = false
    @Published var showIndexRebuildPrompt = false
    @Published var isRebuildingIndex = false
    @Published var indexRebuildMessage = "Preparing to rebuild…"
    @Published var indexRebuildCompletedSteps: Set<IndexRebuildStep> = []
    @Published var indexRebuildActiveStep: IndexRebuildStep?
    @Published var showSavedScanPrompt = false
    @Published var selectedMaintenanceKind: MaintenanceKind = .appCaches
    @Published var maintenanceScanResult: MaintenanceScanResult?
    @Published var maintenanceSelectedEntryIDs: Set<String> = []
    @Published var installedApps: [InstalledApp] = []
    @Published var selectedAppForUninstall: InstalledApp?
    @Published var systemSnapshot: SystemSnapshot?
    @Published var isMaintenanceScanning = false
    @Published var maintenanceStatusMessage = ""
    @Published var optimizationResults: [OptimizationResult] = []
    @Published var isStartingUp = true
    @Published var startupMessage = "Preparing DiskWise…"
    @Published var startupCompletedSteps: Set<StartupStep> = []
    @Published var startupActiveStep: StartupStep?
    @Published var showPythonSetupPrompt = false
    @Published var pythonSetupWizardStep: PythonSetupWizardStep = .needsSetup
    @Published var isPythonAvailable = true
    @Published var usesPythonScanner = false

    let activityLog = ActivityLog.shared
    let appSettings = AppSettings.shared

    private var database: DiskWiseDatabase!
    private var permissionPollTask: Task<Void, Never>?
    private var pythonPollTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var indexRebuildTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var duplicateTask: Task<Void, Never>?
    private var analysisRefreshTask: Task<Void, Never>?
    private var storageAnalysisTask: Task<Void, Never>?
    private var cachedResultsRefreshTask: Task<Void, Never>?
    private var aiChatTask: Task<Void, Never>?
    private var aiChatSessionID = UUID()
    private var scanStartTime: Date?
    private var lastDuplicateGroupsRefreshCount = 0
    private var lastInsightsRefreshCount = 0
    private var scanEngine: ScanEngine!
    private var duplicateEngine: DuplicateEngine!
    private let cleanupEngine = CleanupEngine()
    private var maintenanceEngine = MaintenanceEngine()
    private var aiEngine: AIAnalysisEngine!
    private var aiConsultant: AIConsultantService!
    private let fullDiskAccessPromptKey = "diskwise.hasSeenFullDiskAccessPrompt"
    private let pythonSetupPromptKey = "diskwise.hasSeenPythonSetupPrompt"

    var isPostUpgradeStartup: Bool {
        appSettings.shouldShowWhatsNew
    }

    var isBlockingLaunchFlow: Bool {
        isStartingUp || showPythonSetupPrompt || showFullDiskAccessPrompt || showWhatsNewTour || showIndexRebuildPrompt
    }

    var shouldShowPythonSetupBanner: Bool {
        usesPythonScanner && !isPythonAvailable && !showPythonSetupPrompt
    }

    func schedulePostUpgradePresentation() {
        guard !showFullDiskAccessPrompt, !showPythonSetupPrompt, !showIndexRebuildPrompt else { return }

        if appSettings.shouldShowWhatsNew {
            presentWhatsNewIfNeeded()
            if !isBlockingLaunchFlow {
                schedulePostLaunchWork()
            }
        } else if !isBlockingLaunchFlow {
            presentSavedScanPromptIfNeeded()
            schedulePostLaunchWork()
        }
    }

    /// Runs at most once per day while the main window is open and the app is in the foreground.
    func checkForUpdatesWhenEligible() {
        guard !isBlockingLaunchFlow else { return }
        SparkleUpdaterController.shared.checkForUpdatesInForegroundIfNeeded()
    }

    /// Deferred work after startup overlays (What's New, FDA) so the main UI stays responsive.
    func schedulePostLaunchWork() {
        guard !isBlockingLaunchFlow else { return }
        refreshAnalysisReportInBackground()
    }

    init() {
        AppViewModel.current = self
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
        let pythonScriptURL = PythonScanRunner.bundledScriptURL()
        usesPythonScanner = pythonScriptURL != nil
        scanEngine = ScanEngine(database: openedDatabase, pythonScannerScript: pythonScriptURL)
        duplicateEngine = DuplicateEngine(database: openedDatabase)
        aiConsultant = AIConsultantService(configuration: appSettings.aiProviderConfiguration)
        aiEngine = AIAnalysisEngine(database: openedDatabase, consultant: aiConsultant)
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

        beginStartupStep(.permissions, message: "Checking Full Disk Access…")
        await Task.yield()

        FullDiskAccess.registerForFullDiskAccess()
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        completeStartupStep(.permissions)

        beginStartupStep(.python, message: "Checking Python scanner…")
        await Task.yield()

        isPythonAvailable = !usesPythonScanner || PythonScanRunner.isPythonAvailable
        completeStartupStep(.python)

        overview = nil
        topConsumers = []
        duplicateGroups = []
        analysisReport = nil

        startupActiveStep = nil
        startupMessage = "Ready"
        isStartingUp = false

        refreshAIConfiguration()
        Task { await refreshAIAvailability() }

        presentIndexRebuildPromptIfNeeded()
        presentPythonSetupPromptIfNeeded()
        if !showIndexRebuildPrompt, !showPythonSetupPrompt {
            presentFullDiskAccessPromptIfNeeded()
        }
        if !isBlockingLaunchFlow {
            schedulePostUpgradePresentation()
        }
    }

    func presentPythonSetupPromptIfNeeded() {
        guard usesPythonScanner, !isPythonAvailable else { return }
        guard !showIndexRebuildPrompt else { return }
        guard !UserDefaults.standard.bool(forKey: pythonSetupPromptKey) else { return }

        pythonSetupWizardStep = .needsSetup
        showPythonSetupPrompt = true
        setStatus("Python 3 is required for scanning", kind: .error)
    }

    func presentPythonSetupOverlay() {
        guard usesPythonScanner, !isPythonAvailable else { return }
        pythonSetupWizardStep = .needsSetup
        showPythonSetupPrompt = true
    }

    func runPythonInstallScript() {
        PythonSetupSupport.openInstallScriptInTerminal()
        pythonSetupWizardStep = .waiting
        setStatus("Waiting for Python installation…", kind: .working)
        startPythonPolling()
    }

    func dismissPythonSetupPrompt() {
        stopPythonPolling()
        UserDefaults.standard.set(true, forKey: pythonSetupPromptKey)
        showPythonSetupPrompt = false
        pythonSetupWizardStep = .needsSetup

        if !isPythonAvailable {
            setStatus("Python 3 is required for scanning", kind: .error)
        } else {
            setStatus("Ready to scan", kind: .ready)
        }

        if !showFullDiskAccessPrompt {
            presentFullDiskAccessPromptIfNeeded()
        }
        if !isBlockingLaunchFlow {
            schedulePostUpgradePresentation()
        }
    }

    func cancelPythonSetupWaiting() {
        stopPythonPolling()
        pythonSetupWizardStep = .needsSetup
        dismissPythonSetupPrompt()
    }

    func refreshPythonAvailability() {
        guard usesPythonScanner else {
            isPythonAvailable = true
            return
        }

        isPythonAvailable = PythonScanRunner.isPythonAvailable
        if isPythonAvailable, showPythonSetupPrompt {
            handlePythonInstalled()
        }
    }

    func checkPythonOnAppActivation() {
        guard usesPythonScanner, !isPythonAvailable else { return }
        refreshPythonAvailability()
    }

    private func startPythonPolling() {
        stopPythonPolling()
        pythonPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                refreshPythonAvailability()
            }
        }
    }

    private func stopPythonPolling() {
        pythonPollTask?.cancel()
        pythonPollTask = nil
    }

    private func handlePythonInstalled() {
        guard pythonSetupWizardStep != .ready else { return }

        stopPythonPolling()
        isPythonAvailable = true
        pythonSetupWizardStep = .ready
        setStatus("Python 3 detected — ready to scan", kind: .success)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            showPythonSetupPrompt = false
            pythonSetupWizardStep = .needsSetup
            if !showFullDiskAccessPrompt {
                presentFullDiskAccessPromptIfNeeded()
            }
            if !isBlockingLaunchFlow {
                schedulePostUpgradePresentation()
            }
        }
    }

    func presentSavedScanPromptIfNeeded() {
        guard !showFullDiskAccessPrompt, !showPythonSetupPrompt, !showIndexRebuildPrompt, !showWhatsNewTour else { return }
        guard !appSettings.shouldShowWhatsNew else { return }
        guard let volume = selectedVolume, isIndexed(volume) else {
            presentMenuBarExtensionPromptIfNeeded()
            return
        }
        showSavedScanPrompt = true
    }

    func presentMenuBarExtensionPromptIfNeeded() {
        guard !showFullDiskAccessPrompt, !showPythonSetupPrompt, !showIndexRebuildPrompt, !showWhatsNewTour, !showSavedScanPrompt else { return }
        guard !appSettings.menuBarExtensionPromptDismissed else { return }
        guard !appSettings.showMenuBarDiskMonitor else { return }
        guard appSettings.shouldOfferMenuBarMonitor else { return }

        switch MenuBarExtensionPrompt.presentInstallPrompt() {
        case .install:
            enableMenuBarDiskMonitor()
        case .openSettings, .dismiss:
            appSettings.menuBarExtensionPromptDismissed = true
        }
    }

    func enableMenuBarDiskMonitor() {
        appSettings.setMenuBarDiskMonitorEnabled(true)
        if appSettings.showMenuBarDiskMonitor {
            setStatus("Menu bar disk monitor enabled", kind: .success)
        } else {
            setStatus("Could not enable menu bar monitor", kind: .error)
        }
    }

    func dismissSavedScanPrompt(loadSaved: Bool, rebuild: Bool) {
        showSavedScanPrompt = false
        guard let volume = selectedVolume else { return }

        if rebuild {
            scan(volume: volume)
            return
        }

        if loadSaved {
            refreshInsights()
            setStatus("Loaded saved scan for \(volume.name)", kind: .success)
        } else {
            clearLoadedScanPresentation()
            setStatus("Selected \(volume.name)", kind: .ready)
        }

        presentMenuBarExtensionPromptIfNeeded()
    }

    private func clearLoadedScanPresentation() {
        overview = nil
        topConsumers = []
        duplicateGroups = []
        analysisReport = nil
        clearStorageCategorySelection()
        cachedResultsRefreshTask?.cancel()
        analysisRefreshTask?.cancel()
    }

    func presentIndexRebuildPromptIfNeeded() {
        guard appSettings.needsIndexRebuild else { return }
        guard !showFullDiskAccessPrompt else { return }
        showIndexRebuildPrompt = true
    }

    func dismissIndexRebuildPrompt(rebuildNow: Bool) {
        showIndexRebuildPrompt = false
        if rebuildNow {
            isRebuildingIndex = true
            indexRebuildCompletedSteps = []
            beginIndexRebuildStep(.clearing, message: "Clearing saved storage index…")
            indexRebuildTask?.cancel()
            indexRebuildTask = Task { await rebuildStorageIndex(rescan: true) }
        } else {
            appSettings.markIndexSchemaCurrent()
            schedulePostUpgradePresentation()
        }
    }

    func rebuildStorageIndex(rescan: Bool) async {
        overview = nil
        topConsumers = []
        duplicateGroups = []
        analysisReport = nil
        clearStorageCategorySelection()
        cachedResultsRefreshTask?.cancel()
        analysisRefreshTask?.cancel()

        await Task.yield()

        guard !Task.isCancelled else {
            finishIndexRebuild(success: false, message: "Index rebuild cancelled", kind: .ready)
            return
        }

        do {
            try await Task.detached(priority: .userInitiated) { [database] in
                try database.clearAllStorageIndexes()
            }.value
        } catch {
            finishIndexRebuild(
                success: false,
                message: "Could not clear storage index: \(error.localizedDescription)",
                kind: .error
            )
            return
        }

        completeIndexRebuildStep(.clearing)
        appSettings.markIndexSchemaCurrent()
        reload()

        logActivity(.scan, "Cleared storage index", detail: "Index schema upgraded to v\(AppSettings.currentIndexSchemaVersion)")

        if rescan, let volume = selectedVolume ?? mountedVolumes.first {
            beginIndexRebuildStep(.identifying, message: "Identifying disk usage on \(volume.name)…")
            setStatus("Storage index cleared — rescanning \(volume.name)…", kind: .working)
            scan(volume: volume)
        } else {
            finishIndexRebuild(
                success: true,
                message: "Storage index cleared — scan a drive to rebuild",
                kind: .success
            )
            schedulePostUpgradePresentation()
        }
    }

    private func beginIndexRebuildStep(_ step: IndexRebuildStep, message: String) {
        indexRebuildActiveStep = step
        indexRebuildMessage = message
    }

    private func completeIndexRebuildStep(_ step: IndexRebuildStep) {
        indexRebuildCompletedSteps.insert(step)
    }

    private func finishIndexRebuild(success: Bool, message: String, kind: AppStatusKind) {
        isRebuildingIndex = false
        indexRebuildActiveStep = nil
        indexRebuildCompletedSteps = []
        setStatus(message, kind: kind)
        if success {
            schedulePostUpgradePresentation()
        }
    }

    private func finishIndexRebuildAfterScan(volumeName: String, success: Bool, message: String, kind: AppStatusKind) {
        guard isRebuildingIndex else { return }
        if success {
            completeIndexRebuildStep(.analyzing)
            indexRebuildMessage = "Action plan ready for \(volumeName)"
        }
        finishIndexRebuild(success: success, message: message, kind: kind)
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
        (isScanning || isAnalyzing) && selectedVolumePath == volume.mountPath
    }

    var hasScanData: Bool {
        overview != nil
    }

    var totalDuplicateSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableSize }
    }

    var isBackgroundWorkActive: Bool {
        isAnalyzing
    }

    var scanEstimatedRemaining: TimeInterval? {
        guard let progress = scanProgress,
              let start = scanStartTime,
              progress.scannedCount > 100,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }

        let progressFraction = scanProgressFractionFromBytes
        if progressFraction >= 0.98 {
            return max(5, 30 - elapsed)
        }

        let rate = Double(progress.bytesIndexed) / elapsed
        guard rate > 0 else { return nil }

        let remainingBytes = Double(max(0, volume.usedSize - progress.bytesIndexed))
        let estimate = remainingBytes / rate

        if !hasFullDiskAccess, progressFraction < 0.2 {
            return min(estimate, 1_800)
        }

        return estimate
    }

    var scanProgressFraction: Double {
        if isAnalyzing {
            return 0.85
        }
        if isScanning {
            return min(0.75, scanProgressFractionFromBytes)
        }
        return 0
    }

    var scanProgressFractionFromBytes: Double {
        guard let progress = scanProgress,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return isScanning ? 0.08 : 0
        }

        let byteFraction = min(1.0, Double(progress.bytesIndexed) / Double(volume.usedSize))
        if let processed = progress.directoriesProcessed,
           let total = progress.directoriesTotal,
           total > 0 {
            let directoryFraction = Double(processed) / Double(total)
            let directoryWeight = (progress.operation == .sizingDirectory || progress.operation == .preparing) ? 0.25 : 0.15
            return min(1.0, max(byteFraction, directoryFraction * directoryWeight + byteFraction * (1 - directoryWeight)))
        }
        return byteFraction
    }

    var scanProgressDetail: String? {
        guard let progress = scanProgress else { return nil }
        var parts: [String] = [progress.operation.label]
        if let detail = progress.detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    var scanConcurrencySummary: String? {
        guard let progress = scanProgress,
              let total = progress.directoriesTotal,
              total > 0 else {
            return nil
        }
        let completed = progress.directoriesProcessed ?? 0
        return "\(completed)/\(total) folders"
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
            return "Identifying \(volume.name) · \(scanProgressPercentLabel)"
        }
        if isAnalyzing {
            return "Analyzing storage…"
        }
        if isFindingDuplicates, let detail = duplicateProgressDetail {
            return "Finding duplicates · \(detail)"
        }
        return statusMessage
    }

    func diskRecord(for volume: MountedVolume) -> DiskRecord? {
        disks.first { $0.mountPath == volume.mountPath }
    }

    func isIndexed(_ volume: MountedVolume) -> Bool {
        guard let disk = diskRecord(for: volume), let diskID = disk.id else { return false }
        return ((try? database.indexedFileCount(forDiskID: diskID)) ?? 0) > 0
    }

    func scanActionTitle(for volume: MountedVolume) -> String {
        isIndexed(volume) ? "Rescan \(volume.name)" : "Scan \(volume.name)"
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
        guard isScanning, scanPhase == .identifying else { return }
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
    }

    func refreshFromError() {
        reload()
        refreshMountedVolumes()

        guard let volume = selectedVolume ?? mountedVolumes.first else {
            setStatus("Ready to scan", kind: .ready)
            return
        }

        selectedVolumePath = volume.mountPath
        scan(volume: volume)
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
            schedulePostUpgradePresentation()
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
        setStatus("Waiting for Full Disk Access…", kind: .working)
        startPermissionPolling()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard showFullDiskAccessPrompt, fullDiskAccessWizardStep == .waiting else { return }
            FullDiskAccessSettings.open()
        }
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
        schedulePostUpgradePresentation()
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
        schedulePostUpgradePresentation()
    }

    func presentWhatsNewIfNeeded() {
        guard appSettings.shouldShowWhatsNew else { return }
        guard !showFullDiskAccessPrompt else { return }
        guard !showPythonSetupPrompt else { return }
        guard !showIndexRebuildPrompt else { return }
        showWhatsNewTour = true
    }

    func finishWhatsNewTour() {
        appSettings.markCurrentReleaseSeen()
        showWhatsNewTour = false
        presentSavedScanPromptIfNeeded()
    }

    func stopPermissionPollingIfNeeded() {
        stopPermissionPolling()
    }

    func stopPythonPollingIfNeeded() {
        stopPythonPolling()
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
        let volumeChanged = selectedVolumePath != volume.mountPath
        selectedVolumePath = volume.mountPath
        if let disk = diskRecord(for: volume) {
            selectedDiskID = disk.id
        } else {
            selectedDiskID = nil
        }

        if volumeChanged {
            clearLoadedScanPresentation()
        }

        setStatus("Selected \(volume.name)", kind: .ready)

        if volumeChanged, isIndexed(volume) {
            showSavedScanPrompt = true
            return
        }

        if autoScan && !isIndexed(volume) && !isScanning {
            scan(volume: volume)
        }
    }

    func scanSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive from the sidebar first", kind: .error)
            return
        }
        scan(volume: volume)
    }

    func scanFolderOnSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive from the sidebar first", kind: .error)
            return
        }
        scanFolder(on: volume)
    }

    func scanFolder(on volume: MountedVolume) {
        guard !isVolumeBusy(volume) else { return }
        selectedVolumePath = volume.mountPath
        if let disk = diskRecord(for: volume) {
            selectedDiskID = disk.id
        } else {
            selectedDiskID = nil
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder on \(volume.name) to scan"
        panel.directoryURL = URL(fileURLWithPath: volume.mountPath)

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        guard folderIsOnVolume(folderURL, volume: volume) else {
            setStatus("Choose a folder on \(volume.name)", kind: .error)
            return
        }

        scan(volume: volume, folder: folderURL)
    }

    func scanInternalDrive() {
        if let internalVolume = internalVolumes.first {
            selectedVolumePath = internalVolume.mountPath
            scan(volume: internalVolume)
        } else if let first = mountedVolumes.first {
            selectedVolumePath = first.mountPath
            scan(volume: first)
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
        scanEngine?.cancelActiveScan()
        storageAnalysisTask?.cancel()
        cancelDuplicateDetection()
        isScanning = false
        isAnalyzing = false
        scanPhase = .idle
        scanProgress = nil
        scanStartTime = nil
        ScanActivityMonitor.shared.endScan()
        ScanLogMonitor.shared.endSession()
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

    private func refreshCachedScanResultsInBackground() {
        guard let diskID = selectedDiskID else {
            overview = nil
            topConsumers = []
            duplicateGroups = []
            analysisReport = nil
            return
        }

        cachedResultsRefreshTask?.cancel()
        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        guard let database, let duplicateEngine else { return }

        cachedResultsRefreshTask = Task { @MainActor in
            let snapshot = await Task.detached(priority: .utility) {
                let overview = try? database.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
                let topConsumers = (try? database.topConsumers(forDiskID: diskID, limit: 8)) ?? []
                let duplicateGroups = (try? duplicateEngine.loadGroups(forDiskID: diskID)) ?? []
                return CachedScanSnapshot(
                    overview: overview,
                    topConsumers: topConsumers,
                    duplicateGroups: duplicateGroups
                )
            }.value

            guard !Task.isCancelled else { return }
            overview = snapshot.overview
            topConsumers = snapshot.topConsumers
            duplicateGroups = snapshot.duplicateGroups
        }
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
        refreshAIInsights(for: analysisReport)
    }

    private func refreshAnalysisReportInBackground() {
        guard let diskID = selectedDiskID else {
            analysisReport = nil
            return
        }
        guard !isBlockingLaunchFlow else { return }

        analysisRefreshTask?.cancel()
        let fileLimit = appSettings.analysisFileLimit
        guard let engine = aiEngine else { return }

        analysisRefreshTask = Task { @MainActor in
            let report = await Task.detached(priority: .utility) { () -> AnalysisReport? in
                try? engine.analyze(diskID: diskID, fileLimit: fileLimit)
            }.value

            guard !Task.isCancelled else { return }
            analysisReport = report
            refreshAIInsights(for: report)
        }
    }

    func refreshAIConfiguration() {
        let configuration = appSettings.aiProviderConfiguration
        aiEngine?.updateConsultantConfiguration(configuration)
        aiConsultant?.updateConfiguration(configuration)
        Task { await refreshAIAvailability() }
    }

    func refreshAIAvailability() async {
        guard let consultant = aiConsultant else { return }
        let status = await consultant.providerStatus()
        aiProviderStatus = status

        if let report = analysisReport {
            let context = AIChatContext(report: report, topConsumers: topConsumers)
            aiSuggestedQuestions = await consultant.suggestQuestions(context: context)
        } else {
            aiSuggestedQuestions = []
        }
    }

    func updateAIAutocomplete() {
        guard aiProviderStatus.isGenerativeAvailable else {
            aiAutocompleteSuggestions = []
            return
        }
        guard let report = analysisReport, let consultant = aiConsultant else {
            aiAutocompleteSuggestions = []
            return
        }

        let partial = aiQuestion
        let context = AIChatContext(report: report, topConsumers: topConsumers)
        Task {
            let suggestions = await consultant.autocompleteSuggestions(for: partial, context: context)
            await MainActor.run {
                guard self.aiQuestion == partial else { return }
                self.aiAutocompleteSuggestions = suggestions
            }
        }
    }

    private func refreshAIInsights(for report: AnalysisReport?) {
        guard let report, let consultant = aiConsultant else {
            aiAnalysisSummary = ""
            aiSuggestedQuestions = []
            return
        }

        let context = AIChatContext(report: report, topConsumers: topConsumers)
        Task {
            let suggestions = await consultant.suggestQuestions(context: context)
            let summary = await consultant.enrichAnalysis(context: context)
            await MainActor.run {
                self.aiSuggestedQuestions = suggestions
                self.aiAnalysisSummary = summary ?? ""
            }
        }
    }

    func refreshInsights() {
        refreshCachedScanResultsInBackground()
        refreshAnalysisReportInBackground()
    }

    func scan(volume: MountedVolume, folder: URL? = nil) {
        if usesPythonScanner, !isPythonAvailable {
            presentPythonSetupOverlay()
            setStatus("Python 3 is required for scanning", kind: .error)
            return
        }

        scanTask?.cancel()
        cancelDuplicateDetection()
        selectedPane = .overview
        isScanning = true
        scanPhase = .identifying
        scanStartTime = Date()
        lastInsightsRefreshCount = 0
        lastDuplicateGroupsRefreshCount = 0
        clearStorageCategorySelection()

        let volumeURL = URL(fileURLWithPath: volume.mountPath)
        let scanRoot = folder ?? volumeURL
        let volumeRootPath = volumeURL.standardizedFileURL.path
        let scanRootPath = scanRoot.standardizedFileURL.path
        let isFolderScan = scanRootPath != volumeRootPath
        let scanLabel = isFolderScan
            ? (scanRoot.lastPathComponent.isEmpty ? scanRoot.path : scanRoot.lastPathComponent)
            : volume.name

        selectedVolumePath = volume.mountPath
        if let disk = diskRecord(for: volume) {
            selectedDiskID = disk.id
        } else {
            selectedDiskID = nil
        }
        setStatus("Phase 1 of 3 · \(appSettings.scanMode.title) identify · \(scanLabel)…", kind: .working)
        logActivity(
            .scan,
            isFolderScan ? "Started folder scan" : "Started filesystem scan",
            detail: "\(appSettings.scanMode.title) · \(isFolderScan ? "\(scanLabel) on \(volume.name)" : volume.name)"
        )
        ScanActivityMonitor.shared.beginScan(volumeName: scanLabel)
        ScanLogMonitor.shared.reset()

        let scanMode = appSettings.scanMode
        guard let scanEngine = self.scanEngine else { return }
        scanTask = Task.detached { [weak self, scanEngine, scanMode] in
            guard let self else { return }
            do {
                let summary = try scanEngine.scanVolume(
                    name: volume.name,
                    mountPath: volumeURL,
                    scanRoot: isFolderScan ? scanRoot : nil,
                    mode: scanMode,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.scanProgress = progress
                            self.maybeRefreshInsightsDuringScan(progress)
                            ScanActivityMonitor.shared.update(
                                progressFraction: self.scanProgressFraction,
                                progressPercentLabel: self.scanProgressPercentLabel,
                                detail: self.scanProgressDetail,
                                operationLabel: progress.operation.label
                            )
                            if self.isRebuildingIndex {
                                self.indexRebuildMessage = "Identifying disk usage · \(progress.scannedCount.formatted()) files…"
                            }
                            self.setStatus(
                                "Phase 1 of 3 · \(progress.operation.label) · \(progress.scannedCount.formatted()) files · \(self.scanProgressPercentLabel)",
                                kind: .working
                            )
                        }
                    },
                    onLogLine: { line in
                        Task { @MainActor in
                            ScanLogMonitor.shared.append(line)
                        }
                    },
                    onScanSessionStarted: { session in
                        Task { @MainActor in
                            ScanLogMonitor.shared.beginSession(session)
                        }
                    },
                    isCancelled: {
                        Task.isCancelled
                    }
                )

                await MainActor.run {
                    self.finishFilesystemScan(
                        summary: summary,
                        volumeName: volume.name,
                        scanLabel: scanLabel,
                        volumeMountPath: volume.mountPath
                    )
                }
            } catch {
                await MainActor.run {
                    if self.isRebuildingIndex {
                        self.finishIndexRebuildAfterScan(
                            volumeName: scanLabel,
                            success: false,
                            message: error is CancellationError || error.localizedDescription.contains("cancelled")
                                ? "Index rebuild cancelled"
                                : "Index rebuild failed: \(error.localizedDescription)",
                            kind: error is CancellationError || error.localizedDescription.contains("cancelled") ? .ready : .error
                        )
                    } else if error is CancellationError || error.localizedDescription.contains("cancelled") {
                        self.logActivity(.scan, "Scan cancelled", detail: scanLabel)
                        self.setStatus("Scan cancelled", kind: .ready)
                    } else if Self.isPythonNotFoundError(error) {
                        self.isPythonAvailable = false
                        self.pythonSetupWizardStep = .needsSetup
                        self.showPythonSetupPrompt = true
                        self.logActivity(.scan, "Scan failed", detail: "Python 3 not found")
                        self.setStatus("Python 3 is required for scanning", kind: .error)
                    } else {
                        self.logActivity(.scan, "Scan failed", detail: error.localizedDescription)
                        self.setStatus("Scan failed: \(error.localizedDescription)", kind: .error)
                    }
                    self.isScanning = false
                    self.scanPhase = .idle
                    self.scanProgress = nil
                    self.scanStartTime = nil
                    ScanActivityMonitor.shared.endScan()
                    ScanLogMonitor.shared.endSession()
                }
            }
        }
    }

    private func folderIsOnVolume(_ folder: URL, volume: MountedVolume) -> Bool {
        let root = URL(fileURLWithPath: volume.mountPath).standardizedFileURL.path
        let chosen = folder.standardizedFileURL.path
        return chosen == root || chosen.hasPrefix(root + "/")
    }

    private func finishFilesystemScan(
        summary: ScanSummary,
        volumeName: String,
        scanLabel: String,
        volumeMountPath: String
    ) {
        isScanning = false
        ScanActivityMonitor.shared.endScan()
        ScanLogMonitor.shared.endSession()
        scanPhase = .analyzing
        scanProgress = nil
        selectedDiskID = summary.diskID
        selectedVolumePath = volumeMountPath
        reload()
        refreshInsights()
        if isRebuildingIndex {
            completeIndexRebuildStep(.identifying)
            beginIndexRebuildStep(.analyzing, message: "Analyzing storage on \(volumeName)…")
        }
        let completionDetail = scanLabel == volumeName
            ? "\(summary.scannedFiles.formatted()) files indexed on \(volumeName)"
            : "\(summary.scannedFiles.formatted()) files indexed in \(scanLabel) on \(volumeName)"
        setStatus("Phase 2 of 3 · Analyzing storage on \(volumeName)…", kind: .working)
        logActivity(
            .scan,
            "Disk usage identified",
            detail: completionDetail
        )
        startStorageAnalysis(diskID: summary.diskID, volumeName: volumeName)
    }

    private func startStorageAnalysis(diskID: Int64, volumeName: String) {
        isAnalyzing = true
        scanPhase = .analyzing
        let analysisFileLimit = appSettings.analysisFileLimit
        guard let aiEngine = self.aiEngine else { return }

        storageAnalysisTask?.cancel()
        storageAnalysisTask = Task.detached { [weak self, aiEngine] in
            guard let self else { return }
            do {
                _ = try aiEngine.analyze(diskID: diskID, fileLimit: analysisFileLimit)

                await MainActor.run {
                    self.isAnalyzing = false
                    self.scanPhase = .idle
                    self.scanStartTime = nil
                    self.refreshInsights()
                    self.selectedPane = .overview
                    self.logActivity(.recommendation, "Action plan ready", detail: volumeName)
                    let statusMessage = "Phase 3 of 3 · Action plan ready for \(volumeName)"
                    if self.isRebuildingIndex {
                        self.finishIndexRebuildAfterScan(
                            volumeName: volumeName,
                            success: true,
                            message: statusMessage,
                            kind: .success
                        )
                    } else {
                        self.setStatus(statusMessage, kind: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.scanPhase = .idle
                    self.scanStartTime = nil
                    self.refreshInsights()
                    self.logActivity(.recommendation, "Analysis failed", detail: error.localizedDescription)
                    let statusMessage = "Analysis failed: \(error.localizedDescription) — indexed data is still available"
                    if self.isRebuildingIndex {
                        self.finishIndexRebuildAfterScan(
                            volumeName: volumeName,
                            success: false,
                            message: statusMessage,
                            kind: .error
                        )
                    } else {
                        self.setStatus(statusMessage, kind: .error)
                    }
                }
            }
        }
    }

    func scanForDuplicates() {
        guard let diskID = selectedDiskID else {
            setStatus("Identify disk usage first", kind: .error)
            return
        }
        guard !isFindingDuplicates else { return }

        let volumeName = selectedVolume?.name ?? "drive"
        startDuplicateDetection(diskID: diskID, volumeName: volumeName)
    }

    private func startDuplicateDetection(diskID: Int64, volumeName: String) {
        duplicateTask?.cancel()
        isFindingDuplicates = true
        scanStartTime = Date()
        lastDuplicateGroupsRefreshCount = 0
        let duplicateFileLimit = appSettings.duplicateScanFileLimit
        logActivity(
            .duplicate,
            "Started duplicate detection",
            detail: "\(volumeName) · checking largest \(duplicateFileLimit.formatted()) files"
        )

        guard let duplicateEngine = self.duplicateEngine else { return }
        duplicateTask = Task.detached { [weak self, duplicateEngine] in
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
                                self.setStatus("Finding duplicates · \(detail)", kind: .working)
                            } else {
                                self.setStatus("Finding duplicates on \(volumeName)…", kind: .working)
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
                    self.scanStartTime = nil
                    self.refreshInsights()
                    if duplicateSummary.groupsFound > 0 {
                        self.logActivity(
                            .duplicate,
                            "Duplicate detection complete",
                            detail: "\(duplicateSummary.groupsFound) groups · \(DiskWiseFormatters.bytes.string(fromByteCount: duplicateSummary.reclaimableBytes)) reclaimable"
                        )
                        self.setStatus(
                            "Found \(duplicateSummary.groupsFound) duplicate groups",
                            kind: .success
                        )
                    } else {
                        self.logActivity(.duplicate, "Duplicate detection complete", detail: "No groups found")
                        self.setStatus("No duplicate groups found", kind: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isFindingDuplicates = false
                    self.duplicateScanProgress = nil
                    self.scanStartTime = nil
                    if error is CancellationError || error.localizedDescription.contains("cancelled") {
                        self.logActivity(.duplicate, "Duplicate detection cancelled")
                        self.setStatus("Duplicate check cancelled", kind: .ready)
                    } else {
                        self.logActivity(.duplicate, "Duplicate detection failed", detail: error.localizedDescription)
                        self.setStatus(
                            "Duplicate check failed: \(error.localizedDescription)",
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
                let report = try await aiEngine.requestLLMReport(
                    for: diskID,
                    topConsumers: topConsumers,
                    fileLimit: appSettings.analysisFileLimit
                )
                await MainActor.run {
                    self.llmReport = report
                    self.aiAnalysisSummary = report
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

    func startNewAIChatSession() {
        aiChatSessionID = UUID()
        aiChatTask?.cancel()
        aiChatTask = nil
        aiResponses = []
        aiQuestion = ""
        aiAutocompleteSuggestions = []
        isAITyping = false
    }

    func askAI(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        aiQuestion = ""
        aiAutocompleteSuggestions = []
        aiResponses.append(AIChatMessage(role: .user, text: trimmed))

        guard let report = analysisReport else {
            aiResponses.append(AIChatMessage(
                role: .assistant,
                text: "Scan a drive first so I can analyze your storage and answer questions."
            ))
            return
        }

        let context = AIChatContext(report: report, topConsumers: topConsumers)
        let assistantID = UUID()
        let sessionID = aiChatSessionID
        aiResponses.append(AIChatMessage(id: assistantID, role: .assistant, text: "", isStreaming: true))
        isAITyping = true

        aiChatTask?.cancel()
        aiChatTask = Task {
            let stream = aiConsultant.streamRespond(to: trimmed, context: context)
            var receivedContent = false

            do {
                for try await partial in stream {
                    guard !Task.isCancelled, sessionID == self.aiChatSessionID else { return }
                    receivedContent = true
                    await MainActor.run {
                        guard sessionID == self.aiChatSessionID else { return }
                        self.isAITyping = false
                        self.updateAssistantMessage(id: assistantID, text: partial, isStreaming: true)
                    }
                }

                await MainActor.run {
                    guard sessionID == self.aiChatSessionID else { return }
                    self.isAITyping = false
                    self.updateAssistantMessage(
                        id: assistantID,
                        text: self.assistantMessageText(id: assistantID),
                        isStreaming: false
                    )
                }
            } catch {
                guard !Task.isCancelled, sessionID == self.aiChatSessionID else { return }
                let fallback = Self.answerQuestion(trimmed, report: report, consumers: topConsumers)
                await MainActor.run {
                    guard sessionID == self.aiChatSessionID else { return }
                    self.isAITyping = false
                    if receivedContent {
                        self.updateAssistantMessage(
                            id: assistantID,
                            text: self.assistantMessageText(id: assistantID),
                            isStreaming: false
                        )
                    } else {
                        self.streamFallbackAnswer(id: assistantID, text: fallback, sessionID: sessionID)
                    }
                }
            }
        }
    }

    private func assistantMessageText(id: UUID) -> String {
        aiResponses.first(where: { $0.id == id })?.text ?? ""
    }

    private func updateAssistantMessage(id: UUID, text: String, isStreaming: Bool) {
        guard let index = aiResponses.firstIndex(where: { $0.id == id }) else { return }
        aiResponses[index].text = text
        aiResponses[index].isStreaming = isStreaming
    }

    private func streamFallbackAnswer(id: UUID, text: String, sessionID: UUID) {
        aiChatTask = Task {
            for await partial in Self.simulatedReveal(text) {
                guard !Task.isCancelled, sessionID == self.aiChatSessionID else { return }
                await MainActor.run {
                    guard sessionID == self.aiChatSessionID else { return }
                    self.updateAssistantMessage(id: id, text: partial, isStreaming: true)
                }
            }
            await MainActor.run {
                guard sessionID == self.aiChatSessionID else { return }
                self.updateAssistantMessage(id: id, text: text, isStreaming: false)
            }
        }
    }

    private static func simulatedReveal(_ text: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.finish()
                    return
                }

                var index = trimmed.startIndex
                while index < trimmed.endIndex {
                    let next = trimmed.index(index, offsetBy: 3, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                    continuation.yield(String(trimmed[..<next]))
                    index = next
                    if index < trimmed.endIndex {
                        try? await Task.sleep(for: .milliseconds(18))
                    }
                }
                continuation.finish()
            }
        }
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
        switch recommendation.type {
        case "duplicate_cleanup":
            openDuplicatesPane()
            scanForDuplicates()
        case "project_purge":
            selectedPane = .maintenance
            selectedMaintenanceKind = .nodeModules
            scanMaintenance(.nodeModules)
        case "delete_logs":
            selectedPane = .maintenance
            selectedMaintenanceKind = .logs
            scanMaintenance(.logs)
        case "delete_cache":
            selectedPane = .maintenance
            selectedMaintenanceKind = .appCaches
            scanMaintenance(.appCaches)
        case "thin_apfs_snapshots":
            selectedPane = .maintenance
            selectedMaintenanceKind = .apfsSnapshots
            scanMaintenance(.apfsSnapshots)
        default:
            reviewRecommendation(recommendation)
        }
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
        let bucket = ActionBucket.bucket(forRecommendationType: recommendationType)
        guard bucket.selectsFilesByDefault else {
            if recommendationType == "delete_dmg" {
                return Set(
                    files.compactMap { file -> Int64? in
                        guard let id = file.id else { return nil }
                        let classification = RemovablePathRules.classifyInstallerArtifact(path: file.path, size: file.size)
                        return classification?.selectedByDefault == true ? id : nil
                    }
                )
            }
            return []
        }

        return Set(files.compactMap(\.id))
    }

    private func revealTrashedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Maintenance (Mole-inspired)

    func scanMaintenance(_ kind: MaintenanceKind) {
        selectedMaintenanceKind = kind
        isMaintenanceScanning = true
        maintenanceStatusMessage = "Scanning \(kind.title.lowercased())…"
        setStatus(maintenanceStatusMessage, kind: .working)

        Task.detached { [weak self, maintenanceEngine] in
            guard let self else { return }
            let result: MaintenanceScanResult
            switch kind {
            case .appUninstall:
                let apps = maintenanceEngine.scanInstalledApps()
                await MainActor.run {
                    self.installedApps = apps
                    self.maintenanceScanResult = nil
                    self.isMaintenanceScanning = false
                    self.maintenanceStatusMessage = "Found \(apps.count) installed apps"
                    self.setStatus(self.maintenanceStatusMessage, kind: .success)
                    self.logActivity(.scan, "Scanned installed apps", detail: "\(apps.count) apps")
                }
                return
            case .systemStatus:
                let snapshot = maintenanceEngine.systemSnapshot()
                await MainActor.run {
                    self.systemSnapshot = snapshot
                    self.maintenanceScanResult = nil
                    self.isMaintenanceScanning = false
                    self.maintenanceStatusMessage = "Health score: \(snapshot.healthScore)"
                    self.setStatus("System health: \(snapshot.healthScore)/100", kind: .success)
                }
                return
            case .optimize:
                await MainActor.run {
                    self.optimizationResults = []
                    self.isMaintenanceScanning = false
                    self.maintenanceStatusMessage = "Choose an optimization task below"
                    self.setStatus("Ready to optimize", kind: .ready)
                }
                return
            default:
                result = maintenanceEngine.scan(kind)
            }

            await MainActor.run {
                self.maintenanceScanResult = result
                self.maintenanceSelectedEntryIDs = Set(
                    result.entries.filter(\.selectedByDefault).map(\.id)
                )
                self.isMaintenanceScanning = false
                if kind == .apfsSnapshots {
                    self.maintenanceStatusMessage = "\(result.entries.count) local snapshot(s)"
                    self.setStatus("Found \(result.entries.count) APFS snapshot(s)", kind: .success)
                    self.logActivity(.scan, "Listed APFS snapshots", detail: "\(result.entries.count) snapshots")
                } else {
                    let sizeLabel = DiskWiseFormatters.bytes.string(fromByteCount: result.totalBytes)
                    self.maintenanceStatusMessage = "\(result.entries.count) items · \(sizeLabel) reclaimable"
                    self.setStatus("Found \(result.entries.count) items (\(sizeLabel))", kind: .success)
                    self.logActivity(.scan, "Maintenance scan complete", detail: "\(kind.title) · \(sizeLabel)")
                }
            }
        }
    }

    func toggleMaintenanceEntry(_ entry: MaintenanceEntry) {
        if maintenanceSelectedEntryIDs.contains(entry.id) {
            maintenanceSelectedEntryIDs.remove(entry.id)
        } else {
            maintenanceSelectedEntryIDs.insert(entry.id)
        }
    }

    func selectAllMaintenanceEntries(_ selected: Bool) {
        guard let result = maintenanceScanResult else { return }
        maintenanceSelectedEntryIDs = selected ? Set(result.entries.map(\.id)) : []
    }

    var selectedMaintenanceEntries: [MaintenanceEntry] {
        maintenanceScanResult?.entries.filter { maintenanceSelectedEntryIDs.contains($0.id) } ?? []
    }

    var selectedMaintenanceBytes: Int64 {
        selectedMaintenanceEntries.reduce(0) { $0 + $1.size }
    }

    func executeMaintenanceCleanup() {
        if selectedMaintenanceKind == .apfsSnapshots {
            executeAPFSSnapshotThinning()
            return
        }

        let entries = selectedMaintenanceEntries
        guard !entries.isEmpty else {
            setStatus("Select items to clean", kind: .error)
            return
        }

        setStatus("Moving \(entries.count) items to Trash…", kind: .working)
        let result = maintenanceEngine.executeCleanup(entries: entries)
        reportCleanupResult(result)

        if result.movedCount > 0 {
            maintenanceSelectedEntryIDs = []
            scanMaintenance(selectedMaintenanceKind)
        }
    }

    func executeAPFSSnapshotThinning() {
        let mountPath = selectedVolume?.mountPath ?? "/"
        setStatus("Thinning APFS snapshots…", kind: .working)
        let removed = maintenanceEngine.thinAPFSSnapshots(mountPath: mountPath)
        if removed > 0 {
            logActivity(.cleanup, "Thinned APFS snapshots", detail: "\(removed) removed on \(mountPath)")
            setStatus("Removed \(removed) local snapshot(s) — free space should increase shortly", kind: .success)
        } else {
            setStatus("No local snapshots to remove", kind: .ready)
        }
        scanMaintenance(.apfsSnapshots)
    }

    func uninstallSelectedApp(_ app: InstalledApp) {
        setStatus("Uninstalling \(app.name)…", kind: .working)
        let result = maintenanceEngine.uninstallApp(app)
        reportCleanupResult(result)
        selectedAppForUninstall = nil
        if result.movedCount > 0 {
            scanMaintenance(.appUninstall)
        }
    }

    func runOptimizationTask(_ task: OptimizationTask) {
        setStatus("Running \(task.title)…", kind: .working)
        let result = maintenanceEngine.runOptimization(taskID: task.id)
        optimizationResults.insert(result, at: 0)
        setStatus(result.message, kind: result.succeeded ? .success : .error)
        logActivity(.cleanup, task.title, detail: result.message)
    }

    func refreshSystemSnapshot() {
        systemSnapshot = maintenanceEngine.systemSnapshot()
    }

    var optimizationTasks: [OptimizationTask] {
        maintenanceEngine.optimizationTasks()
    }

    private static func isPythonNotFoundError(_ error: Error) -> Bool {
        if let pythonError = error as? PythonScanRunnerError, case .pythonNotFound = pythonError {
            return true
        }
        return error.localizedDescription.contains("Python 3 is required")
    }

    private func setStatus(_ message: String, kind: AppStatusKind) {
        statusMessage = message
        statusKind = kind
    }
}

struct AIChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool

    init(id: UUID = UUID(), role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}
