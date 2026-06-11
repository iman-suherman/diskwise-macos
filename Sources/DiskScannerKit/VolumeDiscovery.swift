import Foundation

public struct MountedVolume: Identifiable, Sendable, Hashable {
    public var id: String { mountPath }
    public let name: String
    public let mountPath: String
    public let totalSize: Int64
    public let freeSize: Int64
    public let isInternal: Bool
    public let isRemovable: Bool

    public init(
        name: String,
        mountPath: String,
        totalSize: Int64,
        freeSize: Int64,
        isInternal: Bool,
        isRemovable: Bool
    ) {
        self.name = name
        self.mountPath = mountPath
        self.totalSize = totalSize
        self.freeSize = freeSize
        self.isInternal = isInternal
        self.isRemovable = isRemovable
    }

    public var usedSize: Int64 {
        max(0, totalSize - freeSize)
    }

    public var usageFraction: Double {
        guard totalSize > 0 else { return 0 }
        return Double(usedSize) / Double(totalSize)
    }
}

public enum VolumeDiscovery {
    /// APFS system volumes and other non-user-facing mount points to hide from the UI.
    public static let hiddenVolumeNames: Set<String> = [
        "Preboot",
        "VM",
        "Update",
        "Hardware",
        "iSCPreboot",
        "Recovery",
        "Recovery HD",
        "com.apple.os.update-",
    ]

    public static func isHiddenVolume(name: String, mountPath: String) -> Bool {
        if mountPath.hasPrefix("/System/Volumes/") {
            return true
        }

        if hiddenVolumeNames.contains(name) {
            return true
        }

        if hiddenVolumeNames.contains(where: { name.hasPrefix($0) }) {
            return true
        }

        // Hide duplicate APFS data volumes mounted at /Volumes/<name> when root is "/"
        if mountPath.hasPrefix("/Volumes/") {
            let volumeName = URL(fileURLWithPath: mountPath).lastPathComponent
            if hiddenVolumeNames.contains(volumeName) {
                return true
            }
        }

        return false
    }

    public static func mountedVolumes(fileManager: FileManager = .default) -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
        ]

        var volumes: [MountedVolume] = []
        var seenPaths = Set<String>()

        if let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) {
            for url in urls {
                guard let volume = makeVolume(from: url, keys: keys) else { continue }
                guard !isHiddenVolume(name: volume.name, mountPath: volume.mountPath) else { continue }
                guard seenPaths.insert(volume.mountPath).inserted else { continue }
                volumes.append(volume)
            }
        }

        if !seenPaths.contains("/") {
            if let root = makeVolume(from: URL(fileURLWithPath: "/"), keys: keys) {
                volumes.insert(root, at: 0)
            }
        }

        return volumes.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal {
                return lhs.isInternal && !rhs.isInternal
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Paths under `/Volumes` that exist on disk but were not returned by volume discovery.
    public static func unlistedExternalVolumePaths(fileManager: FileManager = .default) -> [String] {
        let discoveredPaths = Set(mountedVolumes(fileManager: fileManager).map(\.mountPath))
        guard let entries = try? fileManager.contentsOfDirectory(atPath: "/Volumes") else {
            return []
        }

        return entries
            .filter { !$0.hasPrefix(".") }
            .map { "/Volumes/\($0)" }
            .filter { path in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                    && !discoveredPaths.contains(path)
            }
            .sorted()
    }

    public static func likelyNeedsFullDiskAccess(fileManager: FileManager = .default) -> Bool {
        mountedVolumes(fileManager: fileManager).isEmpty
            || !unlistedExternalVolumePaths(fileManager: fileManager).isEmpty
    }

    private static func makeVolume(from url: URL, keys: [URLResourceKey]) -> MountedVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }

        let mountPath = url.path
        let localizedName = values.volumeLocalizedName ?? values.volumeName
        let fallbackName = url.lastPathComponent.isEmpty ? mountPath : url.lastPathComponent
        let name = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? localizedName!
            : fallbackName

        let totalSize = Int64(values.volumeTotalCapacity ?? 0)
        let freeSize = Int64(values.volumeAvailableCapacity ?? 0)

        if totalSize == 0 && mountPath != "/" {
            return nil
        }

        let isRemovable = (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false)

        return MountedVolume(
            name: name,
            mountPath: mountPath,
            totalSize: totalSize,
            freeSize: freeSize,
            isInternal: values.volumeIsInternal ?? (mountPath == "/"),
            isRemovable: isRemovable
        )
    }
}
