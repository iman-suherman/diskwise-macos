import Foundation

public struct APFSSnapshotEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let mountPath: String

    public init(name: String, mountPath: String) {
        self.id = "\(mountPath)|\(name)"
        self.name = name
        self.mountPath = mountPath
    }
}

public final class APFSSnapshotScanner: @unchecked Sendable {
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = ProcessRunner()) {
        self.processRunner = processRunner
    }

    /// Lists local Time Machine snapshots on APFS volumes via `tmutil listlocalsnapshots`.
    public func listSnapshots(mountPath: String = "/") -> [APFSSnapshotEntry] {
        let output = processRunner.run(
            executable: "/usr/bin/tmutil",
            arguments: ["listlocalsnapshots", mountPath]
        )
        guard !output.isEmpty else { return [] }

        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("com.apple.TimeMachine") }
            .map { APFSSnapshotEntry(name: $0, mountPath: mountPath) }
    }

    /// Deletes all local snapshots on a volume. Returns the number removed.
    @discardableResult
    public func thinAllSnapshots(mountPath: String = "/") -> Int {
        let snapshots = listSnapshots(mountPath: mountPath)
        guard !snapshots.isEmpty else { return 0 }

        var removed = 0
        for snapshot in snapshots {
            let status = processRunner.run(
                executable: "/usr/bin/tmutil",
                arguments: ["deletelocalsnapshots", snapshot.name]
            )
            if status.isEmpty || !status.lowercased().contains("error") {
                removed += 1
            }
        }
        return removed
    }

    public func scan(mountPath: String = "/") -> MaintenanceScanResult {
        let snapshots = listSnapshots(mountPath: mountPath)
        let entries = snapshots.map { snapshot in
            MaintenanceEntry(
                id: snapshot.id,
                path: snapshot.mountPath,
                label: snapshot.name,
                detail: "Local Time Machine snapshot — may pin deleted file blocks on APFS",
                size: 0,
                category: .apfsSnapshot,
                selectedByDefault: true
            )
        }
        return MaintenanceScanResult(kind: .apfsSnapshots, entries: entries)
    }
}

/// Thin wrapper around Process for testability.
public struct ProcessRunner: Sendable {
    public init() {}

    public func run(executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
