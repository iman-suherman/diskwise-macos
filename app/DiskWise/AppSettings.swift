import Combine
import Foundation
import SwiftUI

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
        case .fast: return "Quicker scans on very large drives"
        case .balanced: return "Recommended for most Macs"
        case .thorough: return "More coverage, longer duplicate checks"
        case .maximum: return "Slowest — checks the most files"
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

    private init() {
        let defaults = UserDefaults.standard
        duplicateScanFileLimit = Self.clamp(
            defaults.object(forKey: Keys.duplicateScanFileLimit) as? Int ?? Self.defaultDuplicateScanFileLimit,
            to: Self.duplicateScanFileLimitRange
        )
        analysisFileLimit = Self.clamp(
            defaults.object(forKey: Keys.analysisFileLimit) as? Int ?? Self.defaultAnalysisFileLimit,
            to: Self.analysisFileLimitRange
        )
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
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
