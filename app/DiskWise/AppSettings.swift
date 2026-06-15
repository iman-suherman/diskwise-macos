import Combine
import Foundation
import SwiftUI
import DiskScannerKit
import AIKit

enum ScanPerformancePreset: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case thorough
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .thorough: return "Thorough"
        case .maximum: return "Maximum"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "Lighter duplicate and analysis limits — usually under 5 minutes after scan"
        case .balanced: return "Recommended duplicate and analysis limits for most Macs"
        case .thorough: return "Broader duplicate checks and deeper analysis sampling"
        case .maximum: return "Maximum duplicate and analysis coverage — slowest option"
        }
    }

    var duplicateScanFileLimit: Int {
        switch self {
        case .fast: return 25_000
        case .balanced: return 100_000
        case .thorough: return 250_000
        case .maximum: return 500_000
        }
    }

    var analysisFileLimit: Int {
        switch self {
        case .fast: return 5_000
        case .balanced: return 10_000
        case .thorough: return 25_000
        case .maximum: return 100_000
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultDuplicateScanFileLimit = 100_000
    static let defaultAnalysisFileLimit = 10_000

    static let duplicateScanFileLimitRange = 10_000...500_000
    static let analysisFileLimitRange = 1_000...100_000

    private enum Keys {
        static let duplicateScanFileLimit = "diskwise.settings.duplicateScanFileLimit"
        static let analysisFileLimit = "diskwise.settings.analysisFileLimit"
        static let lastSeenReleaseVersion = "diskwise.settings.lastSeenReleaseVersion"
        static let indexSchemaVersion = "diskwise.settings.indexSchemaVersion"
        static let aiProviderPreference = "diskwise.settings.aiProviderPreference"
        static let ollamaBaseURL = "diskwise.settings.ollamaBaseURL"
        static let ollamaModel = "diskwise.settings.ollamaModel"
        static let enableOllamaDevMode = "diskwise.settings.enableOllamaDevMode"
        static let menuBarExtensionPromptDismissed = "diskwise.settings.menuBarExtensionPromptDismissed"
        static let showMenuBarDiskMonitor = "diskwise.settings.showMenuBarDiskMonitor"
        static let showMenuBarDiskFreeGB = "diskwise.settings.showMenuBarDiskFreeGB"
        static let menuBarFreeSpaceVolumes = "diskwise.settings.menuBarFreeSpaceVolumes"
        static let showMenuBarHealthScore = "diskwise.settings.showMenuBarHealthScore"
        static let keepAwakeEnabled = "diskwise.settings.keepAwakeEnabled"
        static let keepAwakeVolumePaths = "diskwise.settings.keepAwakeVolumePaths"
        static let hideFromDock = "diskwise.settings.hideFromDock"
        static let launchAtLogin = "diskwise.settings.launchAtLogin"
        static let memoryAnalyzerEnabled = "diskwise.settings.memoryAnalyzerEnabled"
        static let memoryAnalyzerNotificationsEnabled = "diskwise.settings.memoryAnalyzerNotificationsEnabled"
        static let diskSpaceNotificationsEnabled = "diskwise.settings.diskSpaceNotificationsEnabled"
        static let systemHealthNotificationsEnabled = "diskwise.settings.systemHealthNotificationsEnabled"
        static let diskNotificationThresholdMode = "diskwise.settings.diskNotificationThresholdMode"
        static let diskNotificationFreePercent = "diskwise.settings.diskNotificationFreePercent"
        static let diskNotificationFreeGigabytes = "diskwise.settings.diskNotificationFreeGigabytes"
        static let memoryNotificationThresholdMode = "diskwise.settings.memoryNotificationThresholdMode"
        static let memoryNotificationUsedPercent = "diskwise.settings.memoryNotificationUsedPercent"
        static let memoryNotificationFreeGigabytes = "diskwise.settings.memoryNotificationFreeGigabytes"
        static let diskNotificationVolumeOverrides = "diskwise.settings.diskNotificationVolumeOverrides"
        static let menuPaneOrder = "diskwise.settings.menuPaneOrder"
    }

    /// Bump when the storage index format or scan pipeline changes materially.
    static let currentIndexSchemaVersion = 2

    @Published var duplicateScanFileLimit: Int {
        didSet {
            let clamped = Self.clamp(duplicateScanFileLimit, to: Self.duplicateScanFileLimitRange)
            if clamped != duplicateScanFileLimit {
                duplicateScanFileLimit = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.duplicateScanFileLimit)
        }
    }

    @Published var analysisFileLimit: Int {
        didSet {
            let clamped = Self.clamp(analysisFileLimit, to: Self.analysisFileLimitRange)
            if clamped != analysisFileLimit {
                analysisFileLimit = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.analysisFileLimit)
        }
    }

    @Published var aiProviderPreference: AIProviderKind {
        didSet {
            UserDefaults.standard.set(aiProviderPreference.rawValue, forKey: Keys.aiProviderPreference)
        }
    }

    @Published var ollamaBaseURL: String {
        didSet {
            UserDefaults.standard.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL)
        }
    }

    @Published var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel)
        }
    }

    @Published var enableOllamaDevMode: Bool {
        didSet {
            UserDefaults.standard.set(enableOllamaDevMode, forKey: Keys.enableOllamaDevMode)
        }
    }

    @Published var menuBarFreeSpaceVolumePaths: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(menuBarFreeSpaceVolumePaths).sorted(),
                forKey: Keys.menuBarFreeSpaceVolumes
            )
            syncMenuBarMonitorState()
        }
    }

    @Published var showMenuBarHealthScore: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarHealthScore, forKey: Keys.showMenuBarHealthScore)
            syncMenuBarMonitorState()
        }
    }

    @Published var keepAwakeVolumePaths: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(keepAwakeVolumePaths).sorted(),
                forKey: Keys.keepAwakeVolumePaths
            )
            syncKeepAwakeState()
        }
    }

    @Published var hideFromDock: Bool {
        didSet {
            UserDefaults.standard.set(hideFromDock, forKey: Keys.hideFromDock)
        }
    }

    var showMenuBarDiskMonitor: Bool {
        !menuBarFreeSpaceVolumePaths.isEmpty || showMenuBarHealthScore
    }

    func isMenuBarFreeSpaceVisible(for mountPath: String) -> Bool {
        menuBarFreeSpaceVolumePaths.contains(mountPath)
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published var memoryAnalyzerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(memoryAnalyzerEnabled, forKey: Keys.memoryAnalyzerEnabled)
            MemoryAnalyzerMonitor.shared.applySettings(self)
        }
    }

    @Published var memoryAnalyzerNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(memoryAnalyzerNotificationsEnabled, forKey: Keys.memoryAnalyzerNotificationsEnabled)
            if memoryAnalyzerNotificationsEnabled {
                Task {
                    await MemoryInsightNotificationService.shared.requestAuthorizationIfNeeded()
                }
            }
        }
    }

    @Published var diskSpaceNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(diskSpaceNotificationsEnabled, forKey: Keys.diskSpaceNotificationsEnabled)
            if diskSpaceNotificationsEnabled {
                Task {
                    await DiskSpaceNotificationService.shared.requestAuthorizationIfNeeded()
                }
            }
            refreshDiskSpaceNotifications()
        }
    }

    @Published var systemHealthNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(systemHealthNotificationsEnabled, forKey: Keys.systemHealthNotificationsEnabled)
            if systemHealthNotificationsEnabled {
                Task {
                    await SystemHealthNotificationService.shared.requestAuthorizationIfNeeded()
                }
            }
            refreshMemoryUsageNotifications()
        }
    }

    @Published var diskNotificationThresholdMode: NotificationThresholdMode {
        didSet {
            UserDefaults.standard.set(diskNotificationThresholdMode.rawValue, forKey: Keys.diskNotificationThresholdMode)
            refreshDiskSpaceNotifications()
        }
    }

    @Published var diskNotificationFreePercent: Int {
        didSet {
            let clamped = NotificationThresholdLogic.clamp(
                diskNotificationFreePercent,
                to: NotificationThresholdDefaults.diskFreePercentRange
            )
            if clamped != diskNotificationFreePercent {
                diskNotificationFreePercent = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.diskNotificationFreePercent)
            refreshDiskSpaceNotifications()
        }
    }

    @Published var diskNotificationFreeGigabytes: Double {
        didSet {
            let clamped = NotificationThresholdLogic.clamp(
                diskNotificationFreeGigabytes,
                to: NotificationThresholdDefaults.diskFreeGigabytesRange
            )
            if clamped != diskNotificationFreeGigabytes {
                diskNotificationFreeGigabytes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.diskNotificationFreeGigabytes)
            refreshDiskSpaceNotifications()
        }
    }

    @Published var memoryNotificationThresholdMode: NotificationThresholdMode {
        didSet {
            UserDefaults.standard.set(memoryNotificationThresholdMode.rawValue, forKey: Keys.memoryNotificationThresholdMode)
            refreshMemoryUsageNotifications()
        }
    }

    @Published var memoryNotificationUsedPercent: Int {
        didSet {
            let clamped = NotificationThresholdLogic.clamp(
                memoryNotificationUsedPercent,
                to: NotificationThresholdDefaults.memoryUsedPercentRange
            )
            if clamped != memoryNotificationUsedPercent {
                memoryNotificationUsedPercent = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.memoryNotificationUsedPercent)
            refreshMemoryUsageNotifications()
        }
    }

    @Published var memoryNotificationFreeGigabytes: Double {
        didSet {
            let clamped = NotificationThresholdLogic.clamp(
                memoryNotificationFreeGigabytes,
                to: NotificationThresholdDefaults.memoryFreeGigabytesRange
            )
            if clamped != memoryNotificationFreeGigabytes {
                memoryNotificationFreeGigabytes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.memoryNotificationFreeGigabytes)
            refreshMemoryUsageNotifications()
        }
    }

    @Published var diskNotificationVolumeOverrides: [String: DiskNotificationVolumeOverride] {
        didSet {
            saveDiskNotificationVolumeOverrides()
            refreshDiskSpaceNotifications()
        }
    }

    @Published var menuPaneOrder: [DetailPane] {
        didSet {
            UserDefaults.standard.set(
                menuPaneOrder.map(\.rawValue),
                forKey: Keys.menuPaneOrder
            )
        }
    }

    @Published var showMenuBarMonitorInstructions = false

    var menuBarExtensionPromptDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.menuBarExtensionPromptDismissed) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.menuBarExtensionPromptDismissed) }
    }

    var shouldOfferMenuBarMonitor: Bool {
        !showMenuBarDiskMonitor && !menuBarExtensionPromptDismissed
    }

    func setMenuBarDiskMonitorEnabled(_ enabled: Bool) {
        menuBarFreeSpaceVolumePaths = enabled ? ["/"] : []
        showMenuBarHealthScore = enabled
        MenuBarMonitorController.syncMenuBarItems(settings: self)
    }

    func setMenuBarHealthScoreVisible(_ visible: Bool) {
        showMenuBarHealthScore = visible
        MenuBarMonitorController.syncMenuBarItems(settings: self)
    }

    func isKeepAwakeVolumeEnabled(for mountPath: String) -> Bool {
        if VolumeDiscovery.isSystemVolume(mountPath: mountPath) {
            return true
        }
        return keepAwakeVolumePaths.contains(mountPath)
    }

    func setKeepAwakeVolumeEnabled(for mountPath: String, enabled: Bool) {
        if VolumeDiscovery.isSystemVolume(mountPath: mountPath) {
            if enabled {
                keepAwakeVolumePaths.insert(mountPath)
            }
            return
        }
        if enabled {
            keepAwakeVolumePaths.insert(mountPath)
        } else {
            keepAwakeVolumePaths.remove(mountPath)
        }
    }

    private func resolvedKeepAwakeVolumePaths() -> Set<String> {
        var paths = keepAwakeVolumePaths
        paths.insert("/")
        return paths
    }

    private func syncKeepAwakeState() {
        KeepAwakeController.shared.apply(volumePaths: resolvedKeepAwakeVolumePaths())
    }

    func setHideFromDock(_ hidden: Bool) {
        hideFromDock = hidden
        DockVisibilityController.apply(hidden: hidden)
    }

    func setMenuBarFreeSpaceVisible(for mountPath: String, visible: Bool) {
        if visible {
            menuBarFreeSpaceVolumePaths.insert(mountPath)
        } else {
            menuBarFreeSpaceVolumePaths.remove(mountPath)
        }
        MenuBarMonitorController.syncMenuBarItems(settings: self)
    }

    func diskNotificationOverride(for mountPath: String) -> DiskNotificationVolumeOverride {
        diskNotificationVolumeOverrides[mountPath] ?? DiskNotificationVolumeOverride()
    }

    func setDiskNotificationOverride(for mountPath: String, override: DiskNotificationVolumeOverride) {
        diskNotificationVolumeOverrides[mountPath] = override
    }

    func resolvedDiskNotificationSettings(for volume: MountedVolume) -> DiskNotificationResolvedSettings? {
        NotificationThresholdLogic.resolvedDiskSettings(
            for: volume,
            globalMode: diskNotificationThresholdMode,
            globalFreePercent: diskNotificationFreePercent,
            globalFreeGigabytes: diskNotificationFreeGigabytes,
            override: diskNotificationVolumeOverrides[volume.mountPath]
        )
    }

    func refreshDiskSpaceNotifications() {
        Task {
            await DiskSpaceNotificationService.shared.checkVolumes(
                SystemVolumeMonitor.shared.volumes,
                notificationsEnabled: diskSpaceNotificationsEnabled,
                settings: self
            )
        }
    }

    func refreshMemoryUsageNotifications() {
        Task {
            await SystemHealthNotificationService.shared.checkSnapshot(
                SystemHealthMonitor.shared.snapshot,
                notificationsEnabled: systemHealthNotificationsEnabled,
                settings: self
            )
        }
    }

    private func saveDiskNotificationVolumeOverrides() {
        guard let data = try? JSONEncoder().encode(diskNotificationVolumeOverrides) else { return }
        UserDefaults.standard.set(data, forKey: Keys.diskNotificationVolumeOverrides)
    }

    private static func loadDiskNotificationVolumeOverrides(from defaults: UserDefaults) -> [String: DiskNotificationVolumeOverride] {
        guard let data = defaults.data(forKey: Keys.diskNotificationVolumeOverrides),
              let decoded = try? JSONDecoder().decode([String: DiskNotificationVolumeOverride].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func loadThresholdMode(
        from defaults: UserDefaults,
        key: String,
        default defaultMode: NotificationThresholdMode
    ) -> NotificationThresholdMode {
        guard let rawValue = defaults.string(forKey: key),
              let mode = NotificationThresholdMode(rawValue: rawValue) else {
            return defaultMode
        }
        return mode
    }

    private func syncMenuBarMonitorState() {
        UserDefaults.standard.set(showMenuBarDiskMonitor, forKey: Keys.showMenuBarDiskMonitor)
        MenuBarMonitorController.syncMenuBarItems(settings: self)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        MenuBarMonitorController.applyLaunchAtLogin(enabled: enabled, settings: self)
    }

    private init() {
        let defaults = UserDefaults.standard
        if let rawMode = defaults.string(forKey: "diskwise.settings.scanMode"),
           ScanMode(rawValue: rawMode) != nil {
            defaults.removeObject(forKey: "diskwise.settings.scanMode")
        }
        duplicateScanFileLimit = Self.clamp(
            defaults.object(forKey: Keys.duplicateScanFileLimit) as? Int ?? Self.defaultDuplicateScanFileLimit,
            to: Self.duplicateScanFileLimitRange
        )
        analysisFileLimit = Self.clamp(
            defaults.object(forKey: Keys.analysisFileLimit) as? Int ?? Self.defaultAnalysisFileLimit,
            to: Self.analysisFileLimitRange
        )
        if let rawPreference = defaults.string(forKey: Keys.aiProviderPreference),
           let storedPreference = AIProviderKind(rawValue: rawPreference) {
            aiProviderPreference = storedPreference
        } else {
            aiProviderPreference = .automatic
        }
        ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? "http://127.0.0.1:11434"
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.1"
        enableOllamaDevMode = defaults.bool(forKey: Keys.enableOllamaDevMode)
        if let storedPaths = defaults.stringArray(forKey: Keys.menuBarFreeSpaceVolumes) {
            menuBarFreeSpaceVolumePaths = Set(storedPaths)
            showMenuBarHealthScore = defaults.bool(forKey: Keys.showMenuBarHealthScore)
        } else if defaults.object(forKey: Keys.showMenuBarDiskFreeGB) != nil {
            menuBarFreeSpaceVolumePaths = defaults.bool(forKey: Keys.showMenuBarDiskFreeGB) ? ["/"] : []
            showMenuBarHealthScore = defaults.bool(forKey: Keys.showMenuBarHealthScore)
        } else {
            let legacyMonitor = defaults.bool(forKey: Keys.showMenuBarDiskMonitor)
            menuBarFreeSpaceVolumePaths = legacyMonitor ? ["/"] : []
            showMenuBarHealthScore = false
        }
        hideFromDock = defaults.bool(forKey: Keys.hideFromDock)
        if let storedKeepAwakePaths = defaults.stringArray(forKey: Keys.keepAwakeVolumePaths) {
            keepAwakeVolumePaths = Set(storedKeepAwakePaths.filter { $0 != "/" })
        } else {
            keepAwakeVolumePaths = []
        }
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            launchAtLogin = MenuBarMonitorController.launchAtLoginEnabled
        } else {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        if defaults.object(forKey: Keys.memoryAnalyzerEnabled) == nil {
            memoryAnalyzerEnabled = true
        } else {
            memoryAnalyzerEnabled = defaults.bool(forKey: Keys.memoryAnalyzerEnabled)
        }
        if defaults.object(forKey: Keys.memoryAnalyzerNotificationsEnabled) == nil {
            memoryAnalyzerNotificationsEnabled = true
        } else {
            memoryAnalyzerNotificationsEnabled = defaults.bool(forKey: Keys.memoryAnalyzerNotificationsEnabled)
        }
        if defaults.object(forKey: Keys.diskSpaceNotificationsEnabled) == nil {
            diskSpaceNotificationsEnabled = true
        } else {
            diskSpaceNotificationsEnabled = defaults.bool(forKey: Keys.diskSpaceNotificationsEnabled)
        }
        if defaults.object(forKey: Keys.systemHealthNotificationsEnabled) == nil {
            systemHealthNotificationsEnabled = true
        } else {
            systemHealthNotificationsEnabled = defaults.bool(forKey: Keys.systemHealthNotificationsEnabled)
        }
        diskNotificationThresholdMode = Self.loadThresholdMode(
            from: defaults,
            key: Keys.diskNotificationThresholdMode,
            default: .percentage
        )
        diskNotificationFreePercent = NotificationThresholdLogic.clamp(
            defaults.object(forKey: Keys.diskNotificationFreePercent) as? Int
                ?? NotificationThresholdDefaults.diskFreePercent,
            to: NotificationThresholdDefaults.diskFreePercentRange
        )
        diskNotificationFreeGigabytes = NotificationThresholdLogic.clamp(
            defaults.object(forKey: Keys.diskNotificationFreeGigabytes) as? Double
                ?? NotificationThresholdDefaults.diskFreeGigabytes,
            to: NotificationThresholdDefaults.diskFreeGigabytesRange
        )
        memoryNotificationThresholdMode = Self.loadThresholdMode(
            from: defaults,
            key: Keys.memoryNotificationThresholdMode,
            default: .percentage
        )
        memoryNotificationUsedPercent = NotificationThresholdLogic.clamp(
            defaults.object(forKey: Keys.memoryNotificationUsedPercent) as? Int
                ?? NotificationThresholdDefaults.memoryUsedPercent,
            to: NotificationThresholdDefaults.memoryUsedPercentRange
        )
        memoryNotificationFreeGigabytes = NotificationThresholdLogic.clamp(
            defaults.object(forKey: Keys.memoryNotificationFreeGigabytes) as? Double
                ?? NotificationThresholdDefaults.defaultMemoryFreeGigabytes(),
            to: NotificationThresholdDefaults.memoryFreeGigabytesRange
        )
        diskNotificationVolumeOverrides = Self.loadDiskNotificationVolumeOverrides(from: defaults)
        menuPaneOrder = Self.resolvedMenuPaneOrder(
            stored: defaults.stringArray(forKey: Keys.menuPaneOrder)
        )
        syncKeepAwakeState()
    }

    static func resolvedMenuPaneOrder(stored: [String]?) -> [DetailPane] {
        let validPanes = Set(DetailPane.reorderableMenuPanes)
        guard let stored, !stored.isEmpty else {
            return DetailPane.reorderableMenuPanes
        }

        var ordered = stored.compactMap { DetailPane(rawValue: $0) }.filter { $0.isReorderableMenuItem && validPanes.contains($0) }
        for pane in DetailPane.reorderableMenuPanes where !ordered.contains(pane) {
            ordered.append(pane)
        }
        return ordered
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var lastSeenReleaseVersion: String {
        UserDefaults.standard.string(forKey: Keys.lastSeenReleaseVersion) ?? ""
    }

    var shouldShowWhatsNew: Bool {
        lastSeenReleaseVersion != Self.currentAppVersion
    }

    var storedIndexSchemaVersion: Int {
        let stored = UserDefaults.standard.integer(forKey: Keys.indexSchemaVersion)
        return stored > 0 ? stored : 0
    }

    var needsIndexRebuild: Bool {
        storedIndexSchemaVersion < Self.currentIndexSchemaVersion
    }

    func markIndexSchemaCurrent() {
        UserDefaults.standard.set(Self.currentIndexSchemaVersion, forKey: Keys.indexSchemaVersion)
    }

    func markCurrentReleaseSeen() {
        UserDefaults.standard.set(Self.currentAppVersion, forKey: Keys.lastSeenReleaseVersion)
    }

    var activePreset: ScanPerformancePreset? {
        ScanPerformancePreset.allCases.first { preset in
            preset.duplicateScanFileLimit == duplicateScanFileLimit
                && preset.analysisFileLimit == analysisFileLimit
        }
    }

    func applyPreset(_ preset: ScanPerformancePreset) {
        duplicateScanFileLimit = preset.duplicateScanFileLimit
        analysisFileLimit = preset.analysisFileLimit
    }

    func resetToDefaults() {
        duplicateScanFileLimit = Self.defaultDuplicateScanFileLimit
        analysisFileLimit = Self.defaultAnalysisFileLimit
        aiProviderPreference = .automatic
        ollamaBaseURL = "http://127.0.0.1:11434"
        ollamaModel = "llama3.1"
        enableOllamaDevMode = false
        menuBarFreeSpaceVolumePaths = []
        showMenuBarHealthScore = false
        keepAwakeVolumePaths = []
        hideFromDock = false
        launchAtLogin = false
        memoryAnalyzerEnabled = true
        memoryAnalyzerNotificationsEnabled = true
        diskSpaceNotificationsEnabled = true
        systemHealthNotificationsEnabled = true
        diskNotificationThresholdMode = .percentage
        diskNotificationFreePercent = NotificationThresholdDefaults.diskFreePercent
        diskNotificationFreeGigabytes = NotificationThresholdDefaults.diskFreeGigabytes
        memoryNotificationThresholdMode = .percentage
        memoryNotificationUsedPercent = NotificationThresholdDefaults.memoryUsedPercent
        memoryNotificationFreeGigabytes = NotificationThresholdDefaults.defaultMemoryFreeGigabytes()
        diskNotificationVolumeOverrides = [:]
        showMenuBarMonitorInstructions = false
        MenuBarHealthItemController.shared.syncVisibility(showHealthScore: false)
        DockVisibilityController.apply(hidden: false)
        try? MenuBarMonitorController.launchAtLoginService.unregister()
    }

    var aiProviderConfiguration: AIProviderConfiguration {
        AIProviderConfiguration(
            preference: aiProviderPreference,
            ollamaBaseURL: URL(string: ollamaBaseURL) ?? URL(string: "http://127.0.0.1:11434")!,
            ollamaModel: ollamaModel,
            enableOllamaDevMode: enableOllamaDevMode
        )
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
