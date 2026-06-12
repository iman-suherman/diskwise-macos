import Foundation

public final class DeepCleanScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String

    public init(fileManager: FileManager = .default, homeDirectory: String? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
    }

    public func scan(
        categories: Set<MaintenanceCategory>? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> MaintenanceScanResult {
        var entries: [MaintenanceEntry] = []
        let filter = categories

        if filter == nil || filter?.contains(.userAppCache) == true {
            for target in cacheTargets() {
                if isCancelled?() == true { break }
                appendIfPresent(target, category: .userAppCache, to: &entries)
            }
        }

        if filter == nil || filter?.contains(.browserCache) == true {
            for target in browserTargets() {
                if isCancelled?() == true { break }
                appendIfPresent(target, category: .browserCache, to: &entries)
            }
        }

        if filter == nil || filter?.contains(.developerTools) == true {
            for target in developerTargets() {
                if isCancelled?() == true { break }
                appendIfPresent(target, category: .developerTools, to: &entries)
            }
        }

        if filter == nil || filter?.contains(.systemLogs) == true {
            for target in logTargets() {
                if isCancelled?() == true { break }
                appendIfPresent(target, category: .systemLogs, to: &entries, selectedByDefault: true)
            }
        }

        if filter == nil || filter?.contains(.tempFiles) == true {
            for target in tempTargets() {
                if isCancelled?() == true { break }
                appendIfPresent(target, category: .tempFiles, to: &entries)
            }
        }

        if filter == nil || filter?.contains(.trash) == true {
            if isCancelled?() != true {
                appendTrash(to: &entries)
            }
        }

        let kind: MaintenanceKind = {
            guard let filter, filter.count == 1, let only = filter.first else {
                return .appCaches
            }
            switch only {
            case .userAppCache: return .appCaches
            case .browserCache: return .browserCaches
            case .developerTools: return .developerCaches
            case .systemLogs: return .logs
            case .tempFiles: return .tempFiles
            case .trash: return .trash
            default: return .appCaches
            }
        }()

        return MaintenanceScanResult(kind: kind, entries: entries.sorted { $0.size > $1.size })
    }

    private func cacheTargets() -> [(path: String, label: String)] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library/Caches")
        return [
            (library, "User App Caches"),
            ((homeDirectory as NSString).appendingPathComponent("Library/HTTPStorages"), "HTTP Storage"),
            ((homeDirectory as NSString).appendingPathComponent("Library/Saved Application State"), "Saved Application State"),
        ]
    }

    private func browserTargets() -> [(path: String, label: String)] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library")
        return [
            ((library as NSString).appendingPathComponent("Caches/com.apple.Safari"), "Safari Cache"),
            ((library as NSString).appendingPathComponent("Caches/Google/Chrome"), "Chrome Cache"),
            ((library as NSString).appendingPathComponent("Caches/Firefox"), "Firefox Cache"),
            ((library as NSString).appendingPathComponent("Caches/com.brave.Browser"), "Brave Cache"),
            ((library as NSString).appendingPathComponent("Caches/com.microsoft.edgemac"), "Edge Cache"),
            ((library as NSString).appendingPathComponent("Caches/com.operasoftware.Opera"), "Opera Cache"),
        ]
    }

    private func developerTargets() -> [(path: String, label: String)] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library")
        return [
            ((library as NSString).appendingPathComponent("Developer/Xcode/DerivedData"), "Xcode DerivedData"),
            ((library as NSString).appendingPathComponent("Developer/Xcode/Archives"), "Xcode Archives"),
            ((library as NSString).appendingPathComponent("Developer/CoreSimulator/Caches"), "CoreSimulator Caches"),
            ((library as NSString).appendingPathComponent("Caches/org.swift.swiftpm"), "SwiftPM Cache"),
            ((homeDirectory as NSString).appendingPathComponent(".npm/_cacache"), "npm Cache"),
            ((homeDirectory as NSString).appendingPathComponent(".gradle/caches"), "Gradle Cache"),
            ((homeDirectory as NSString).appendingPathComponent(".cargo/registry/cache"), "Cargo Cache"),
            ((homeDirectory as NSString).appendingPathComponent(".docker"), "Docker Data"),
            ((library as NSString).appendingPathComponent("Caches/Homebrew"), "Homebrew Cache"),
            ((library as NSString).appendingPathComponent("Caches/CocoaPods"), "CocoaPods Cache"),
        ]
    }

    private func logTargets() -> [(path: String, label: String)] {
        let library = (homeDirectory as NSString).appendingPathComponent("Library")
        return [
            ((library as NSString).appendingPathComponent("Logs"), "User Logs"),
            ((library as NSString).appendingPathComponent("Logs/DiagnosticReports"), "Diagnostic Reports"),
            ((library as NSString).appendingPathComponent("Logs/CrashReporter"), "Crash Reports"),
        ]
    }

    private func tempTargets() -> [(path: String, label: String)] {
        [
            (NSTemporaryDirectory(), "Temporary Files"),
            ((homeDirectory as NSString).appendingPathComponent("Library/Caches/com.apple.nsurlsessiond"), "URL Session Cache"),
        ]
    }

    private func appendTrash(to entries: inout [MaintenanceEntry]) {
        let trashPath = (homeDirectory as NSString).appendingPathComponent(".Trash")
        appendIfPresent((trashPath, "Trash"), category: .trash, to: &entries, selectedByDefault: false)
    }

    private func appendIfPresent(
        _ target: (path: String, label: String),
        category: MaintenanceCategory,
        to entries: inout [MaintenanceEntry],
        selectedByDefault: Bool = true
    ) {
        let isTrash = category == .trash
        guard isTrash || ProtectedPathRules.isSafeCleanupPath(target.path, homeDirectory: homeDirectory) else {
            return
        }
        guard fileManager.fileExists(atPath: target.path) else { return }

        let size = DirectorySizeCalculator.sizeOfItem(at: target.path, fileManager: fileManager)
        guard size > 0 else { return }

        entries.append(
            MaintenanceEntry(
                path: target.path,
                label: target.label,
                detail: target.path,
                size: size,
                category: category,
                selectedByDefault: selectedByDefault,
                modifiedAt: DirectorySizeCalculator.modificationDate(at: target.path, fileManager: fileManager)
            )
        )
    }
}
