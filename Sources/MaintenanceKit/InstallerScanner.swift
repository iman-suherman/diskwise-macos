import Foundation
import DatabaseKit

public final class InstallerScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String

    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "zip", "iso", "xip",
    ]

    public init(fileManager: FileManager = .default, homeDirectory: String? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
    }

    public func scan(isCancelled: (@Sendable () -> Bool)? = nil) -> MaintenanceScanResult {
        var entries: [MaintenanceEntry] = []

        for folder in searchFolders() {
            if isCancelled?() == true { break }
            scanFolder(folder, sourceLabel: sourceLabel(for: folder), into: &entries, isCancelled: isCancelled)
        }

        let homebrewCache = (homeDirectory as NSString).appendingPathComponent("Library/Caches/Homebrew/downloads")
        scanFolder(homebrewCache, sourceLabel: "Homebrew", into: &entries, isCancelled: isCancelled, filesOnly: true)

        return MaintenanceScanResult(kind: .installers, entries: entries.sorted { $0.size > $1.size })
    }

    private func searchFolders() -> [String] {
        [
            (homeDirectory as NSString).appendingPathComponent("Downloads"),
            (homeDirectory as NSString).appendingPathComponent("Desktop"),
            (homeDirectory as NSString).appendingPathComponent("Documents"),
        ]
    }

    private func sourceLabel(for folder: String) -> String {
        URL(fileURLWithPath: folder).lastPathComponent
    }

    private func scanFolder(
        _ folder: String,
        sourceLabel: String,
        into entries: inout [MaintenanceEntry],
        isCancelled: (@Sendable () -> Bool)?,
        filesOnly: Bool = false
    ) {
        guard fileManager.fileExists(atPath: folder) else { return }

        if filesOnly {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: folder) else { return }
            for name in contents {
                if isCancelled?() == true { return }
                let path = (folder as NSString).appendingPathComponent(name)
                appendInstallerFile(path: path, sourceLabel: sourceLabel, to: &entries)
            }
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: folder),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let url as URL in enumerator {
            if isCancelled?() == true { return }
            appendInstallerFile(path: url.path, sourceLabel: sourceLabel, to: &entries)
        }
    }

    private func appendInstallerFile(path: String, sourceLabel: String, to entries: inout [MaintenanceEntry]) {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard Self.installerExtensions.contains(ext) || RemovablePathRules.isUserManagedInstallerArtifact(path) else {
            return
        }
        guard ProtectedPathRules.isSafeCleanupPath(path, homeDirectory: homeDirectory)
            || path.contains("/Library/Caches/Homebrew/") else {
            return
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { return }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let classification = RemovablePathRules.classifyInstallerArtifact(path: path, size: size)

        entries.append(
            MaintenanceEntry(
                path: path,
                label: name,
                detail: "\(sourceLabel) · \(classification?.label ?? "Installer")",
                size: size,
                category: .installerImages,
                selectedByDefault: classification?.selectedByDefault ?? true,
                modifiedAt: attributes?[.modificationDate] as? Date
            )
        )
    }
}
