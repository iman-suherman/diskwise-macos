import Foundation
import DatabaseKit

/// Limits indexed file rows to the storage volume they belong on.
public struct VolumeFileScope: Sendable, Equatable {
    public let includePathPrefixes: [String]
    public let excludePathPrefixes: [String]

    public init(includePathPrefixes: [String], excludePathPrefixes: [String]) {
        self.includePathPrefixes = includePathPrefixes.map(Self.normalizePrefix)
        self.excludePathPrefixes = excludePathPrefixes.map(Self.normalizePrefix)
    }

    public static func forVolume(_ volume: MountedVolume, allVolumes: [MountedVolume]) -> VolumeFileScope {
        if VolumeDiscovery.isSystemVolume(mountPath: volume.mountPath) {
            let excludes = allVolumes
                .filter { !VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) }
                .flatMap { pathPrefixes(for: $0) }
            return VolumeFileScope(
                includePathPrefixes: ["/System/Volumes/Data"],
                excludePathPrefixes: excludes
            )
        }

        return VolumeFileScope(
            includePathPrefixes: pathPrefixes(for: volume),
            excludePathPrefixes: []
        )
    }

    /// Paths under the Data volume that should not be descended during a system-volume scan.
    public static func nestedVolumeScanExclusions(
        forScannedVolume volume: MountedVolume,
        allVolumes: [MountedVolume]
    ) -> [String] {
        guard VolumeDiscovery.isSystemVolume(mountPath: volume.mountPath) else { return [] }
        return allVolumes
            .filter { !VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) }
            .compactMap { dataVolumePrefix(for: $0) }
    }

    public var pathScopeFilter: PathScopeFilter {
        PathScopeFilter(
            includePathPrefixes: includePathPrefixes,
            excludePathPrefixes: excludePathPrefixes
        )
    }

    public func matches(_ path: String) -> Bool {
        pathScopeFilter.matches(path)
    }

    private static func pathPrefixes(for volume: MountedVolume) -> [String] {
        var prefixes = [volume.mountPath]
        if let dataPrefix = dataVolumePrefix(for: volume),
           !prefixes.contains(dataPrefix) {
            prefixes.append(dataPrefix)
        }
        return prefixes
    }

    private static func dataVolumePrefix(for volume: MountedVolume) -> String? {
        let name = URL(fileURLWithPath: volume.mountPath).lastPathComponent
        guard !name.isEmpty else { return nil }
        let dataPath = "/System/Volumes/Data/Volumes/\(name)"
        guard dataPath != volume.mountPath else { return nil }
        return dataPath
    }

    private static func normalizePrefix(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/" { return standardized }
        return standardized.hasSuffix("/") ? standardized : standardized + "/"
    }
}
