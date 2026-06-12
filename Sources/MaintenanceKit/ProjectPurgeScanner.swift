import Foundation

public final class ProjectPurgeScanner: @unchecked Sendable {
    public struct Configuration: Sendable {
        public let scanRoots: [String]
        public let recentProjectDays: Int
        public let artifactNames: Set<String>

        public init(
            scanRoots: [String]? = nil,
            recentProjectDays: Int = 7,
            artifactNames: Set<String>? = nil
        ) {
            self.recentProjectDays = recentProjectDays
            self.artifactNames = artifactNames ?? [
                "node_modules",
                "target",
                ".build",
                "build",
                "dist",
                "venv",
                ".venv",
                "__pycache__",
                ".next",
                ".turbo",
                "DerivedData",
            ]
            if let scanRoots {
                self.scanRoots = scanRoots
            } else {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                self.scanRoots = [
                    (home as NSString).appendingPathComponent("Projects"),
                    (home as NSString).appendingPathComponent("GitHub"),
                    (home as NSString).appendingPathComponent("dev"),
                    (home as NSString).appendingPathComponent("Developer"),
                    (home as NSString).appendingPathComponent("Documents"),
                    (home as NSString).appendingPathComponent("src"),
                ]
            }
        }
    }

    private let fileManager: FileManager
    private let homeDirectory: String
    private let configuration: Configuration

    public init(
        fileManager: FileManager = .default,
        homeDirectory: String? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        self.configuration = configuration
    }

    public func scan(isCancelled: (@Sendable () -> Bool)? = nil) -> MaintenanceScanResult {
        var entries: [MaintenanceEntry] = []

        for root in configuration.scanRoots {
            if isCancelled?() == true { break }
            guard ProtectedPathRules.isUserHomePath(root, homeDirectory: homeDirectory) else { continue }
            guard fileManager.fileExists(atPath: root) else { continue }
            scanDirectory(root, into: &entries, isCancelled: isCancelled)
        }

        return MaintenanceScanResult(kind: .projectPurge, entries: entries.sorted { $0.size > $1.size })
    }

    private func scanDirectory(
        _ root: String,
        into entries: inout [MaintenanceEntry],
        isCancelled: (@Sendable () -> Bool)?
    ) {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let url as URL in enumerator {
            if isCancelled?() == true { return }

            let name = url.lastPathComponent
            guard configuration.artifactNames.contains(name) else { continue }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let path = url.path
            guard ProtectedPathRules.isSafeCleanupPath(path, homeDirectory: homeDirectory) else { continue }

            let size = DirectorySizeCalculator.sizeOfItem(at: path, fileManager: fileManager)
            guard size > 10_000_000 else { continue }

            let projectName = projectName(for: url)
            let isRecent = DirectorySizeCalculator.isRecent(at: path, days: configuration.recentProjectDays, fileManager: fileManager)
            let category = category(for: name)

            entries.append(
                MaintenanceEntry(
                    path: path,
                    label: projectName,
                    detail: name,
                    size: size,
                    category: category,
                    selectedByDefault: !isRecent,
                    isRecent: isRecent,
                    modifiedAt: DirectorySizeCalculator.modificationDate(at: path, fileManager: fileManager)
                )
            )

            enumerator.skipDescendants()
        }
    }

    private func projectName(for artifactURL: URL) -> String {
        var current = artifactURL.deletingLastPathComponent()
        while current.path != "/" {
            let name = current.lastPathComponent
            if !configuration.artifactNames.contains(name), !name.hasPrefix(".") {
                return name
            }
            current.deleteLastPathComponent()
        }
        return artifactURL.deletingLastPathComponent().lastPathComponent
    }

    private func category(for artifactName: String) -> MaintenanceCategory {
        switch artifactName {
        case "node_modules": return .nodeModules
        case "venv", ".venv": return .virtualEnv
        default: return .buildArtifacts
        }
    }
}
