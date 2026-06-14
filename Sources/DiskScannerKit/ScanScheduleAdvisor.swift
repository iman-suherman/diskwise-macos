import Foundation

public struct VolumeScanScheduleConfig: Sendable, Codable, Equatable {
    public var fastScanEnabled: Bool
    public var deepScanEnabled: Bool
    public var fastScanHour: Int
    public var fastScanWeekdays: [Int]
    public var deepScanHour: Int
    public var deepScanWeekdays: [Int]

    public init(
        fastScanEnabled: Bool = false,
        deepScanEnabled: Bool = false,
        fastScanHour: Int = 6,
        fastScanWeekdays: [Int] = [2, 3, 4, 5, 6, 7],
        deepScanHour: Int = 2,
        deepScanWeekdays: [Int] = [1]
    ) {
        self.fastScanEnabled = fastScanEnabled
        self.deepScanEnabled = deepScanEnabled
        self.fastScanHour = fastScanHour
        self.fastScanWeekdays = fastScanWeekdays
        self.deepScanHour = deepScanHour
        self.deepScanWeekdays = deepScanWeekdays
    }
}

public enum ScanScheduleAdvisor {
    public static func recommendedSchedule() -> VolumeScanScheduleConfig {
        VolumeScanScheduleConfig(
            fastScanEnabled: false,
            deepScanEnabled: false,
            fastScanHour: 6,
            fastScanWeekdays: [2, 3, 4, 5, 6, 7],
            deepScanHour: 2,
            deepScanWeekdays: [1]
        )
    }

    public static func recommendedScheduleWithBothEnabled() -> VolumeScanScheduleConfig {
        var config = recommendedSchedule()
        config.fastScanEnabled = true
        config.deepScanEnabled = true
        return config
    }

    public static func fastScanSummary(for config: VolumeScanScheduleConfig) -> String {
        guard config.fastScanEnabled else { return "Off" }
        return "\(weekdaySummary(config.fastScanWeekdays)) at \(hourLabel(config.fastScanHour))"
    }

    public static func deepScanSummary(for config: VolumeScanScheduleConfig) -> String {
        guard config.deepScanEnabled else { return "Off" }
        return "\(weekdaySummary(config.deepScanWeekdays)) at \(hourLabel(config.deepScanHour))"
    }

    public static func fastScanRationale() -> String {
        "Run a fast scan on weekday mornings before you start work — usually under 5 minutes and keeps breakdowns current."
    }

    public static func deepScanRationale() -> String {
        "Run a deep scan once a week in the early hours when the Mac is idle — best for complete coverage on large drives."
    }

    public static func hourLabel(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = normalized
        components.minute = 0
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private static func weekdaySummary(_ weekdays: [Int]) -> String {
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
        let symbols = Calendar.current.shortWeekdaySymbols
        let labels = sorted.compactMap { weekday -> String? in
            guard weekday >= 1, weekday <= 7 else { return nil }
            return symbols[weekday - 1]
        }
        return labels.isEmpty ? "Custom" : labels.joined(separator: ", ")
    }
}
