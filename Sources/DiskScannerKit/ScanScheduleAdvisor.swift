import Foundation

public struct ScanScheduleEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var scanMode: String
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int
    public var weekdays: [Int]

    public var idForSchedule: UUID { id }

    public init(
        id: UUID = UUID(),
        scanMode: String,
        isEnabled: Bool = false,
        hour: Int,
        minute: Int = 0,
        weekdays: [Int]
    ) {
        self.id = id
        self.scanMode = scanMode
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays.sorted()
    }

    public var mode: ScanMode {
        ScanMode(rawValue: scanMode) ?? .fast
    }

    public var title: String {
        mode.title + " scan"
    }
}

public struct VolumeScanScheduleConfig: Sendable, Codable, Equatable {
    public var entries: [ScanScheduleEntry]

    public init(entries: [ScanScheduleEntry] = ScanScheduleAdvisor.recommendedEntries()) {
        self.entries = entries
    }

    public var hasEnabledEntries: Bool {
        entries.contains { $0.isEnabled }
    }

    public func entry(for mode: ScanMode) -> ScanScheduleEntry? {
        entries.first { $0.mode == mode }
    }

    public mutating func setEnabled(_ enabled: Bool, for mode: ScanMode) {
        if let index = entries.firstIndex(where: { $0.mode == mode }) {
            entries[index].isEnabled = enabled
        }
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case fastScanEnabled
        case deepScanEnabled
        case fastScanHour
        case fastScanWeekdays
        case deepScanHour
        case deepScanWeekdays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let entries = try container.decodeIfPresent([ScanScheduleEntry].self, forKey: .entries) {
            self.entries = entries
            return
        }

        let fastEnabled = try container.decodeIfPresent(Bool.self, forKey: .fastScanEnabled) ?? false
        let deepEnabled = try container.decodeIfPresent(Bool.self, forKey: .deepScanEnabled) ?? false
        let fastHour = try container.decodeIfPresent(Int.self, forKey: .fastScanHour) ?? 6
        let fastDays = try container.decodeIfPresent([Int].self, forKey: .fastScanWeekdays) ?? [2, 3, 4, 5, 6, 7]
        let deepHour = try container.decodeIfPresent(Int.self, forKey: .deepScanHour) ?? 2
        let deepDays = try container.decodeIfPresent([Int].self, forKey: .deepScanWeekdays) ?? [1]

        self.entries = [
            ScanScheduleEntry(scanMode: ScanMode.fast.rawValue, isEnabled: fastEnabled, hour: fastHour, weekdays: fastDays),
            ScanScheduleEntry(scanMode: ScanMode.deep.rawValue, isEnabled: deepEnabled, hour: deepHour, weekdays: deepDays),
        ]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}

public enum ScanScheduleAdvisor {
    public static let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    public static func recommendedEntries(enabled: Bool = false) -> [ScanScheduleEntry] {
        [
            ScanScheduleEntry(
                scanMode: ScanMode.fast.rawValue,
                isEnabled: enabled,
                hour: 6,
                weekdays: [2, 3, 4, 5, 6, 7]
            ),
            ScanScheduleEntry(
                scanMode: ScanMode.deep.rawValue,
                isEnabled: enabled,
                hour: 2,
                weekdays: [1]
            ),
        ]
    }

    public static func recommendedSchedule() -> VolumeScanScheduleConfig {
        VolumeScanScheduleConfig(entries: recommendedEntries())
    }

    public static func recommendedScheduleWithBothEnabled() -> VolumeScanScheduleConfig {
        VolumeScanScheduleConfig(entries: recommendedEntries(enabled: true))
    }

    public static func entrySummary(_ entry: ScanScheduleEntry) -> String {
        guard entry.isEnabled else { return "Off" }
        return "\(weekdaySummary(entry.weekdays)) at \(timeLabel(hour: entry.hour, minute: entry.minute))"
    }

    public static func fastScanSummary(for config: VolumeScanScheduleConfig) -> String {
        guard let entry = config.entry(for: .fast) else { return "Off" }
        return entrySummary(entry)
    }

    public static func deepScanSummary(for config: VolumeScanScheduleConfig) -> String {
        guard let entry = config.entry(for: .deep) else { return "Off" }
        return entrySummary(entry)
    }

    public static func fastScanRationale() -> String {
        "Run a fast scan on weekday mornings before you start work — usually under 5 minutes and keeps breakdowns current."
    }

    public static func deepScanRationale() -> String {
        "Run a deep scan once a week in the early hours when the Mac is idle — best for complete coverage on large drives."
    }

    public static func timeLabel(hour: Int, minute: Int = 0) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24
        let normalizedMinute = max(0, min(59, minute))
        let formatter = DateFormatter()
        formatter.dateFormat = normalizedMinute == 0 ? "h a" : "h:mm a"
        var components = DateComponents()
        components.hour = normalizedHour
        components.minute = normalizedMinute
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    public static func hourLabel(_ hour: Int) -> String {
        timeLabel(hour: hour)
    }

    public static func weekdaySummary(_ weekdays: [Int]) -> String {
        let sorted = Set(weekdays).sorted()
        if sorted == [2, 3, 4, 5, 6, 7] {
            return "Weekdays"
        }
        if sorted == [1] {
            return "Sunday"
        }
        if sorted.count == 7 {
            return "Daily"
        }
        let labels = sorted.compactMap { weekday -> String? in
            guard weekday >= 1, weekday <= 7 else { return nil }
            return weekdaySymbols[weekday - 1]
        }
        return labels.isEmpty ? "Custom" : labels.joined(separator: ", ")
    }

    public static func weekdayOptions() -> [(value: Int, label: String)] {
        (1...7).map { ($0, weekdaySymbols[$0 - 1]) }
    }

    public static func frequencyPresets() -> [(title: String, weekdays: [Int])] {
        [
            ("Daily", [1, 2, 3, 4, 5, 6, 7]),
            ("Weekdays", [2, 3, 4, 5, 6, 7]),
            ("Weekends", [1, 7]),
            ("Sunday", [1]),
            ("Monday", [2]),
        ]
    }
}
