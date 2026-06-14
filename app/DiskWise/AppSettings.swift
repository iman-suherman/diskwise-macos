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
        case .fast: return "Fast scan + lighter duplicate checks — usually under 5 minutes"
        case .balanced: return "Fast scan with recommended duplicate coverage"
        case .thorough: return "Deep scan with broader duplicate checks"
        case .maximum: return "Deep scan — indexes every file, slowest option"
        }
    }

    var scanMode: ScanMode {
        switch self {
        case .fast, .balanced: return .fast
        case .thorough, .maximum: return .deep
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
    static let defaultScanMode = ScanMode.fast

    static let duplicateScanFileLimitRange = 10_000...500_000
    static let analysisFileLimitRange = 1_000...100_000

    private enum Keys {
        static let scanMode = "diskwise.settings.scanMode"
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
    }

    /// Bump when the storage index format or scan pipeline changes materially.
    static let currentIndexSchemaVersion = 2

    @Published var scanMode: ScanMode {
        didSet {
            UserDefaults.standard.set(scanMode.rawValue, forKey: Keys.scanMode)
        }
    }

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

    private func syncMenuBarMonitorState() {
        UserDefaults.standard.set(showMenuBarDiskMonitor, forKey: Keys.showMenuBarDiskMonitor)
        MenuBarMonitorController.syncMenuBarItems(settings: self)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        MenuBarMonitorController.applyLaunchAtLogin(enabled: enabled, settings: self)
    }

    private init() {
        let defaults = UserDefaults.standard
        if let rawMode = defaults.string(forKey: Keys.scanMode),
           let storedMode = ScanMode(rawValue: rawMode) {
            scanMode = storedMode
        } else {
            scanMode = Self.defaultScanMode
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
        syncKeepAwakeState()
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
            preset.scanMode == scanMode
                && preset.duplicateScanFileLimit == duplicateScanFileLimit
                && preset.analysisFileLimit == analysisFileLimit
        }
    }

    func applyPreset(_ preset: ScanPerformancePreset) {
        scanMode = preset.scanMode
        duplicateScanFileLimit = preset.duplicateScanFileLimit
        analysisFileLimit = preset.analysisFileLimit
    }

    func resetToDefaults() {
        scanMode = Self.defaultScanMode
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
