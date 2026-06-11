import Foundation
import DatabaseKit

public struct CleanupItem: Identifiable, Sendable {
    public let id: Int64
    public let path: String
    public let size: Int64

    public init(id: Int64, path: String, size: Int64) {
        self.id = id
        self.path = path
        self.size = size
    }
}

public struct CleanupPreview: Sendable {
    public let items: [CleanupItem]
    public let totalBytes: Int64

    public init(items: [CleanupItem], totalBytes: Int64) {
        self.items = items
        self.totalBytes = totalBytes
    }
}

public struct CleanupFailure: Identifiable, Sendable {
    public let path: String
    public let reason: String

    public var id: String { path }

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct CleanupResult: Sendable {
    public let movedCount: Int
    public let movedBytes: Int64
    public let trashedURLs: [URL]
    public let failures: [CleanupFailure]

    public init(
        movedCount: Int,
        movedBytes: Int64,
        trashedURLs: [URL],
        failures: [CleanupFailure] = []
    ) {
        self.movedCount = movedCount
        self.movedBytes = movedBytes
        self.trashedURLs = trashedURLs
        self.failures = failures
    }

    public var attemptedCount: Int {
        movedCount + failures.count
    }
}

public enum CleanupError: Error, LocalizedError {
    case itemNotFound(String)
    case trashFailed(String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let path):
            return "File not found: \(path)"
        case .trashFailed(let path, let underlying):
            return "Failed to move \(path) to Trash: \(underlying.localizedDescription)"
        }
    }
}

public final class TrashManager: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(url: URL) throws -> URL {
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            return (resultingURL as URL?) ?? url
        } catch {
            throw CleanupError.trashFailed(url.path, underlying: error)
        }
    }
}

public final class CleanupEngine: @unchecked Sendable {
    private let trashManager: TrashManager

    public init(trashManager: TrashManager = TrashManager()) {
        self.trashManager = trashManager
    }

    public static func canTrashFile(atPath path: String) -> (allowed: Bool, reason: String?) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return (false, "File no longer exists on disk")
        }
        guard fileManager.isReadableFile(atPath: path) else {
            return (false, "DiskWise cannot read this file — grant Full Disk Access")
        }
        guard fileManager.isDeletableFile(atPath: path) else {
            return (false, "macOS blocked removal — file may be protected or in use")
        }
        return (true, nil)
    }

    public func preview(files: [FileRecord], keepFirstInEachGroup: Bool = true) -> CleanupPreview {
        let sorted = files.sorted { $0.path < $1.path }
        let candidates = keepFirstInEachGroup ? Array(sorted.dropFirst()) : sorted
        let items = candidates.compactMap { file -> CleanupItem? in
            let id = file.id ?? Self.stablePathID(file.path)
            return CleanupItem(id: id, path: file.path, size: file.size)
        }
        let totalBytes = items.reduce(0) { $0 + $1.size }
        return CleanupPreview(items: items, totalBytes: totalBytes)
    }

    public func execute(preview: CleanupPreview) -> CleanupResult {
        var movedCount = 0
        var movedBytes: Int64 = 0
        var trashedURLs: [URL] = []
        var failures: [CleanupFailure] = []

        for item in preview.items {
            let eligibility = Self.canTrashFile(atPath: item.path)
            guard eligibility.allowed else {
                failures.append(
                    CleanupFailure(
                        path: item.path,
                        reason: eligibility.reason ?? "Cannot move this file to Trash"
                    )
                )
                continue
            }

            let url = URL(fileURLWithPath: item.path)
            do {
                let trashed = try trashManager.moveToTrash(url: url)
                movedCount += 1
                movedBytes += item.size
                trashedURLs.append(trashed)
            } catch {
                failures.append(
                    CleanupFailure(path: item.path, reason: error.localizedDescription)
                )
            }
        }

        return CleanupResult(
            movedCount: movedCount,
            movedBytes: movedBytes,
            trashedURLs: trashedURLs,
            failures: failures
        )
    }

    private static func stablePathID(_ path: String) -> Int64 {
        Int64(bitPattern: UInt64(abs(path.hashValue)))
    }
}
