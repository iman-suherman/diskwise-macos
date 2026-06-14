import Foundation

public enum MemoryProcessRules {
    public static func isDiskWise(_ processName: String) -> Bool {
        processName.lowercased().contains("diskwise")
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
