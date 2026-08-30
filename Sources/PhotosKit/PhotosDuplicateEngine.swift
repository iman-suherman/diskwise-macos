import Foundation

public struct PhotosDuplicateEngine: Sendable {
    public init() {}

    /// Groups assets that share an exact fingerprint (type, size, dimensions, duration).
    public func findExactDuplicates(in assets: [PhotoAssetRecord]) -> [PhotosDuplicateGroup] {
        let grouped = Dictionary(grouping: assets, by: \.exactFingerprint)
        return grouped
            .filter { $0.value.count > 1 }
            .map { fingerprint, members in
                PhotosDuplicateGroup(
                    id: "exact-\(fingerprint)",
                    fingerprint: fingerprint,
                    assets: members.sorted { $0.byteSize > $1.byteSize }
                )
            }
            .sorted { $0.reclaimableSize > $1.reclaimableSize }
    }

    /// Near-duplicates: same calendar day, same media type, dimensions within 2%, size within 8%.
    /// Excludes assets already claimed by exact duplicate groups.
    public func findSimilar(
        in assets: [PhotoAssetRecord],
        excludingIDs: Set<String> = []
    ) -> [PhotosDuplicateGroup] {
        let candidates = assets.filter { !excludingIDs.contains($0.id) && !$0.isScreenshot }
        let byDay = Dictionary(grouping: candidates) { asset -> String in
            guard let date = asset.creationDate else { return "unknown" }
            return Self.dayKey(date)
        }

        var groups: [PhotosDuplicateGroup] = []
        for (day, dayAssets) in byDay where dayAssets.count > 1 {
            var used = Set<String>()
            for i in 0..<dayAssets.count {
                let seed = dayAssets[i]
                if used.contains(seed.id) { continue }
                var cluster = [seed]
                used.insert(seed.id)
                for j in (i + 1)..<dayAssets.count {
                    let other = dayAssets[j]
                    if used.contains(other.id) { continue }
                    if Self.isSimilar(seed, other) {
                        cluster.append(other)
                        used.insert(other.id)
                    }
                }
                if cluster.count > 1 {
                    let fingerprint = "similar-\(day)-\(seed.pixelWidth)x\(seed.pixelHeight)"
                    groups.append(
                        PhotosDuplicateGroup(
                            id: fingerprint + "-\(cluster[0].id)",
                            fingerprint: fingerprint,
                            assets: cluster.sorted { $0.byteSize > $1.byteSize }
                        )
                    )
                }
            }
        }
        return groups.sorted { $0.reclaimableSize > $1.reclaimableSize }
    }

    public static func isSimilar(_ a: PhotoAssetRecord, _ b: PhotoAssetRecord) -> Bool {
        guard a.mediaType == b.mediaType else { return false }
        guard a.pixelWidth > 0, a.pixelHeight > 0, b.pixelWidth > 0, b.pixelHeight > 0 else {
            return false
        }
        let widthRatio = Double(abs(a.pixelWidth - b.pixelWidth)) / Double(max(a.pixelWidth, b.pixelWidth))
        let heightRatio = Double(abs(a.pixelHeight - b.pixelHeight)) / Double(max(a.pixelHeight, b.pixelHeight))
        guard widthRatio <= 0.02, heightRatio <= 0.02 else { return false }

        let maxSize = max(a.byteSize, b.byteSize)
        guard maxSize > 0 else { return false }
        let sizeRatio = Double(abs(a.byteSize - b.byteSize)) / Double(maxSize)
        guard sizeRatio <= 0.08 else { return false }

        if a.isVideo || b.isVideo {
            let maxDuration = max(a.durationSeconds, b.durationSeconds)
            if maxDuration > 0 {
                let durationRatio = abs(a.durationSeconds - b.durationSeconds) / maxDuration
                if durationRatio > 0.05 { return false }
            }
        }
        return true
    }

    private static func dayKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }
}
