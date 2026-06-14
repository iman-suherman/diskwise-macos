import Foundation

public enum MemoryProcessRules {
    public static func isDiskWise(_ processName: String) -> Bool {
        processName.lowercased().contains("diskwise")
    }

    /// Maps helper/agent process labels to the user-facing app name shown in the Dock.
    public static func userFacingApplicationName(for processName: String) -> String {
        var name = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }

        if let helperRange = name.range(of: " Helper", options: .caseInsensitive) {
            name = String(name[..<helperRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        return name
    }

    public static func isBrowserProcess(_ processName: String) -> Bool {
        let nameLower = userFacingApplicationName(for: processName).lowercased()
        return nameLower.contains("chrome")
            || nameLower.contains("safari")
            || nameLower.contains("firefox")
            || nameLower.contains("edge")
    }

    public static func highMemoryUsageDetail(
        for processName: String,
        averageGB: Double,
        sampleCount: Int
    ) -> String {
        if isDiskWise(processName) {
            return "DiskWise averages \(String(format: "%.1f", averageGB)) GB across \(sampleCount) samples after indexing work. Memory usually drops after scans finish; quit and reopen if it stays high while idle."
        }
        return "\(processName) consistently uses \(String(format: "%.1f", averageGB)) GB. Restarting can reclaim memory from a long-running session."
    }
}
