import Foundation
import DatabaseKit
import UniformTypeIdentifiers

public struct ScannedFile: Sendable {
    public let path: String
    public let size: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let lastAccessed: Date?
    public let extensionName: String?
    public let isDirectory: Bool

    public init(
        path: String,
        size: Int64,
        createdAt: Date?,
        modifiedAt: Date?,
        lastAccessed: Date?,
        extensionName: String?,
        isDirectory: Bool
    ) {
        self.path = path
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastAccessed = lastAccessed
        self.extensionName = extensionName
        self.isDirectory = isDirectory
    }
}

public struct ScanProgress: Sendable {
    public let scannedCount: Int
    public let currentPath: String
    public let bytesIndexed: Int64

    public init(scannedCount: Int, currentPath: String, bytesIndexed: Int64) {
        self.scannedCount = scannedCount
        self.currentPath = currentPath
        self.bytesIndexed = bytesIndexed
    }
}

public struct ScanSummary: Sendable {
    public let diskID: Int64
    public let scannedFiles: Int
    public let indexedBytes: Int64
    public let duration: TimeInterval
    public let mode: ScanMode

    public init(
        diskID: Int64,
        scannedFiles: Int,
        indexedBytes: Int64,
        duration: TimeInterval,
        mode: ScanMode = .fast
    ) {
        self.diskID = diskID
        self.scannedFiles = scannedFiles
        self.indexedBytes = indexedBytes
        self.duration = duration
        self.mode = mode
    }
}

public enum FileClassifier {
    public static func category(for url: URL, isDirectory: Bool) -> FileCategory {
        if isDirectory {
            return categoryForDirectory(at: url)
        }

        let path = url.path
        let pathLower = path.lowercased()

        if pathLower.contains("/downloads/") || pathLower.hasSuffix("/downloads") {
            return .downloads
        }
        if pathLower.contains("/library/caches/") || pathLower.contains("/.cache/") {
            return .cache
        }
        if pathLower.contains("/library/containers/") {
            return .containers
        }
        if pathLower.contains("/library/developer/") || pathLower.contains("/deriveddata/")
            || pathLower.contains("/.docker/") || pathLower.contains("/library/application support/docker")
            || pathLower.contains("/.npm/") || pathLower.contains("/.cargo/") || pathLower.contains("/node_modules/")
            || pathLower.contains("/vendor/") || pathLower.contains("/.venv/") || pathLower.contains("/venv/")
            || pathLower.contains("/pods/") || pathLower.contains("/__pycache__/")
            || pathLower.contains("/target/") || pathLower.contains("/deriveddata/")
            || pathLower.contains("/.next/") || pathLower.contains("/.turbo/")
        {
            return .development
        }
        if pathLower.contains("mobilesync/backup") || pathLower.contains("/ios backup")
            || pathLower.contains("/backup.backupdb/")
        {
            return .backup
        }
        if pathLower.hasSuffix(".vmdk") || pathLower.hasSuffix(".vdi") || pathLower.hasSuffix(".vhd")
            || pathLower.contains("/virtual machines/")
        {
            return .virtualMachines
        }

        let ext = url.pathExtension.lowercased()
        if VideoFileRules.extensions.contains(ext) {
            return .video
        }

        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff", "raw", "cr2", "nef":
            return .photo
        case "pdf", "doc", "docx", "txt", "md", "rtf", "pages", "xls", "xlsx", "ppt", "pptx":
            return .document
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return .archive
        case "app":
            return .application
        case "dmg", "sparseimage", "backup", "ipsw":
            return .backup
        case "tmp", "temp", "partial", "download":
            return .temporary
        case "cache", "cached":
            return .cache
        default:
            let lastComponent = url.lastPathComponent.lowercased()
            if lastComponent.contains("preview") || lastComponent.contains("thumb") {
                return .temporary
            }
            return .other
        }
    }

    private static func categoryForDirectory(at url: URL) -> FileCategory {
        let pathLower = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()

        if name == "downloads" { return .downloads }
        if name == "caches" || pathLower.contains("/library/caches") { return .cache }
        if name == "containers" || pathLower.contains("/library/containers") { return .containers }
        if name == "developer" || name == "deriveddata" || name == "docker" { return .development }
        if name == "applications" || pathLower.hasSuffix("/applications") { return .application }
        if name.contains("virtual machines") { return .virtualMachines }
        return .other
    }

    public static func mimeType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.identifier
    }

    /// Derives a human-readable space consumer name from a file path.
    public static func consumerName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents

        if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            return components[appIndex].replacingOccurrences(of: ".app", with: "")
        }

        if let containersIndex = components.firstIndex(of: "Containers"), containersIndex + 1 < components.count {
            return components[containersIndex + 1]
        }

        if let downloadsIndex = components.firstIndex(of: "Downloads") {
            if downloadsIndex + 1 < components.count {
                return "Downloads/\(components[downloadsIndex + 1])"
            }
            return "Downloads"
        }

        if path.contains("/Library/Developer") || path.contains("/DerivedData") {
            return "Xcode"
        }
        if path.contains("/.docker") || path.contains("Docker") {
            return "Docker"
        }
        if path.contains("/Library/Application Support/Adobe") {
            return "Adobe Creative Cloud"
        }

        if components.count >= 3 {
            return components[2]
        }

        return url.deletingLastPathComponent().lastPathComponent.isEmpty
            ? "Other"
            : url.deletingLastPathComponent().lastPathComponent
    }
}
