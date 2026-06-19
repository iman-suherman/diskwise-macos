import Foundation

public final class AppUninstallScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String
    private let applicationRoots: [String]

    public init(
        fileManager: FileManager = .default,
        homeDirectory: String? = nil,
        applicationRoots: [String]? = nil
    ) {
        self.fileManager = fileManager
        let resolvedHome = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        self.homeDirectory = resolvedHome
        self.applicationRoots = applicationRoots ?? [
            "/Applications",
            (resolvedHome as NSString).appendingPathComponent("Applications"),
        ]
    }

    public func scan(isCancelled: (@Sendable () -> Bool)? = nil) -> [InstalledApp] {
        var apps: [InstalledApp] = []

        for root in applicationRoots {
            if isCancelled?() == true { break }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for name in contents where name.hasSuffix(".app") {
                if isCancelled?() == true { break }
                let bundlePath = (root as NSString).appendingPathComponent(name)
                if let app = makeInstalledApp(bundlePath: bundlePath) {
                    apps.append(app)
                }
            }
        }

        return apps.sorted { $0.totalSize > $1.totalSize }
    }

    public func appBundleExists(_ app: InstalledApp) -> Bool {
        fileManager.fileExists(atPath: app.bundlePath)
    }

    /// Re-validates bundle and related files against disk. Returns `nil` when nothing remains.
    public func refreshInstalledApp(_ app: InstalledApp) -> InstalledApp? {
        if fileManager.fileExists(atPath: app.bundlePath) {
            return makeInstalledApp(bundlePath: app.bundlePath)
        }

        let leftovers = relatedFiles(forAppName: app.name, bundleID: app.bundleID)
        guard !leftovers.isEmpty else { return nil }

        return InstalledApp(
            name: app.name,
            bundlePath: app.bundlePath,
            bundleID: app.bundleID,
            size: 0,
            version: app.version,
            relatedFiles: leftovers
        )
    }

    public func refreshInstalledApps(_ apps: [InstalledApp]) -> [InstalledApp] {
        apps.compactMap { refreshInstalledApp($0) }
    }

    private func makeInstalledApp(bundlePath: String) -> InstalledApp? {
        guard fileManager.fileExists(atPath: bundlePath) else { return nil }

        let bundleURL = URL(fileURLWithPath: bundlePath)
        let name = bundleURL.deletingPathExtension().lastPathComponent
        let bundleID = bundleIdentifier(for: bundleURL)
        let size = DirectorySizeCalculator.sizeOfItem(at: bundlePath, fileManager: fileManager)
        let version = bundleVersion(for: bundleURL)
        let related = relatedFiles(forAppName: name, bundleID: bundleID)

        return InstalledApp(
            name: name,
            bundlePath: bundlePath,
            bundleID: bundleID,
            size: size,
            version: version,
            relatedFiles: related
        )
    }

    private func bundleIdentifier(for bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    private func bundleVersion(for bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
    }

    private func relatedFiles(forAppName name: String, bundleID: String?) -> [MaintenanceEntry] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library")
        var candidates: [(path: String, label: String, category: MaintenanceCategory)] = []

        candidates.append(
            ((library as NSString).appendingPathComponent("Application Support/\(name)"), "Application Support", .appSupportFiles)
        )
        candidates.append(
            ((library as NSString).appendingPathComponent("Caches/\(name)"), "Caches", .appSupportFiles)
        )
        candidates.append(
            ((library as NSString).appendingPathComponent("Logs/\(name)"), "Logs", .appSupportFiles)
        )
        candidates.append(
            ((library as NSString).appendingPathComponent("Saved Application State"), "Saved State", .appSupportFiles)
        )

        if let bundleID {
            candidates.append(
                ((library as NSString).appendingPathComponent("Containers/\(bundleID)"), "Container", .appSupportFiles)
            )
            candidates.append(
                ((library as NSString).appendingPathComponent("Preferences/\(bundleID).plist"), "Preferences", .appSupportFiles)
            )
            candidates.append(
                ((library as NSString).appendingPathComponent("WebKit/\(bundleID)"), "WebKit Storage", .appSupportFiles)
            )
            candidates.append(
                ((library as NSString).appendingPathComponent("Saved Application State/\(bundleID).savedState"), "Saved State", .appSupportFiles)
            )
            candidates.append(
                ((library as NSString).appendingPathComponent("LaunchAgents/\(bundleID).plist"), "Launch Agent", .appSupportFiles)
            )
        }

        var entries: [MaintenanceEntry] = []
        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard ProtectedPathRules.isSafeCleanupPath(candidate.path, homeDirectory: homeDirectory) else { continue }

            let size = DirectorySizeCalculator.sizeOfItem(at: candidate.path, fileManager: fileManager)
            guard size > 0 else { continue }

            entries.append(
                MaintenanceEntry(
                    path: candidate.path,
                    label: candidate.label,
                    detail: candidate.path,
                    size: size,
                    category: candidate.category,
                    selectedByDefault: true
                )
            )
        }

        return entries.sorted { $0.size > $1.size }
    }

    public func entriesForUninstall(app: InstalledApp, includeAppBundle: Bool = true) -> [MaintenanceEntry] {
        var entries = app.relatedFiles.filter { fileManager.fileExists(atPath: $0.path) }
        if includeAppBundle, fileManager.fileExists(atPath: app.bundlePath) {
            entries.insert(
                MaintenanceEntry(
                    path: app.bundlePath,
                    label: app.name,
                    detail: "Application bundle",
                    size: app.size,
                    category: .applicationBundle,
                    selectedByDefault: true
                ),
                at: 0
            )
        }
        return entries
    }
}
