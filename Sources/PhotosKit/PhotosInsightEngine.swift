import Foundation

public struct PhotosInsightOptions: Sendable {
    public var largeVideoBytes: Int64
    public var oldMediaAge: TimeInterval
    public var referenceDate: Date

    public init(
        largeVideoBytes: Int64 = 100 * 1024 * 1024,
        oldMediaAge: TimeInterval = 365 * 2 * 24 * 60 * 60,
        referenceDate: Date = Date()
    ) {
        self.largeVideoBytes = largeVideoBytes
        self.oldMediaAge = oldMediaAge
        self.referenceDate = referenceDate
    }
}

public struct PhotosInsightEngine: Sendable {
    private let duplicateEngine: PhotosDuplicateEngine
    private let options: PhotosInsightOptions

    public init(
        duplicateEngine: PhotosDuplicateEngine = PhotosDuplicateEngine(),
        options: PhotosInsightOptions = PhotosInsightOptions()
    ) {
        self.duplicateEngine = duplicateEngine
        self.options = options
    }

    public func analyze(_ assets: [PhotoAssetRecord]) -> PhotosLibraryReport {
        let exactGroups = duplicateEngine.findExactDuplicates(in: assets)
        let exactIDs = Set(exactGroups.flatMap { $0.assets.map(\.id) })
        let similarGroups = duplicateEngine.findSimilar(in: assets, excludingIDs: exactIDs)

        var claimed = Set<String>()
        var buckets: [PhotosBucketSummary] = []
        var recommendations: [PhotosRecommendation] = []

        func appendBucket(
            _ bucket: PhotosClutterBucket,
            ids: [String],
            reclaimable: Int64,
            title: String,
            detail: String
        ) {
            let unique = ids.filter { claimed.insert($0).inserted }
            guard !unique.isEmpty else { return }
            let bytes: Int64
            if reclaimable > 0 {
                bytes = reclaimable
            } else {
                bytes = assets.filter { unique.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
            }
            buckets.append(PhotosBucketSummary(bucket: bucket, assetIDs: unique, reclaimableBytes: bytes))
            recommendations.append(
                PhotosRecommendation(
                    bucket: bucket,
                    title: title,
                    detail: detail,
                    estimatedSavings: bytes,
                    assetIDs: unique
                )
            )
        }

        let exactCleanupIDs = exactGroups.flatMap(\.suggestedCleanupIDs)
        let exactReclaimable = exactGroups.reduce(Int64(0)) { $0 + $1.reclaimableSize }
        appendBucket(
            .exactDuplicates,
            ids: exactCleanupIDs,
            reclaimable: exactReclaimable,
            title: "Remove exact duplicates",
            detail: "Keep one copy per group; extras go to Recently Deleted."
        )

        let similarCleanupIDs = similarGroups.flatMap(\.suggestedCleanupIDs)
        let similarReclaimable = similarGroups.reduce(Int64(0)) { $0 + $1.reclaimableSize }
        appendBucket(
            .similar,
            ids: similarCleanupIDs,
            reclaimable: similarReclaimable,
            title: "Review similar media",
            detail: "Near-matches from the same day — confirm before cleaning."
        )

        let screenshotIDs = assets.filter { $0.isScreenshot && !claimed.contains($0.id) }.map(\.id)
        appendBucket(
            .screenshots,
            ids: screenshotIDs,
            reclaimable: 0,
            title: "Clean up screenshots",
            detail: "Screenshots are easy to re-capture if you still need them."
        )

        let burstExtras = burstCleanupIDs(in: assets, claimed: claimed)
        appendBucket(
            .bursts,
            ids: burstExtras,
            reclaimable: 0,
            title: "Thin burst sequences",
            detail: "Keep the best frame; send extras to Recently Deleted."
        )

        let largeVideoIDs = assets
            .filter { $0.isVideo && $0.byteSize >= options.largeVideoBytes && !claimed.contains($0.id) }
            .sorted { $0.byteSize > $1.byteSize }
            .map(\.id)
        appendBucket(
            .largeVideos,
            ids: largeVideoIDs,
            reclaimable: 0,
            title: "Review large videos",
            detail: "Videos over 100 MB — keep favorites, archive or remove the rest."
        )

        let cutoff = options.referenceDate.addingTimeInterval(-options.oldMediaAge)
        let oldIDs = assets
            .filter { asset in
                guard let created = asset.creationDate else { return false }
                return created < cutoff && !asset.isFavorite && !claimed.contains(asset.id)
            }
            .map(\.id)
        appendBucket(
            .oldMedia,
            ids: oldIDs,
            reclaimable: 0,
            title: "Review older media",
            detail: "Items older than two years that are not marked favorite."
        )

        let orderedBuckets = PhotosClutterBucket.allCases.compactMap { kind in
            buckets.first { $0.bucket == kind }
        }
        let orderedRecs = PhotosClutterBucket.allCases.compactMap { kind in
            recommendations.first { $0.bucket == kind }
        }

        return PhotosLibraryReport(
            totalAssets: assets.count,
            totalBytes: assets.reduce(0) { $0 + $1.byteSize },
            buckets: orderedBuckets,
            exactDuplicateGroups: exactGroups,
            similarGroups: similarGroups,
            recommendations: orderedRecs.sorted { $0.estimatedSavings > $1.estimatedSavings }
        )
    }

    private func burstCleanupIDs(in assets: [PhotoAssetRecord], claimed: Set<String>) -> [String] {
        let bursts = assets.filter { $0.isBurst && !claimed.contains($0.id) }
        let byBurst = Dictionary(grouping: bursts) { $0.burstIdentifier ?? $0.id }
        var ids: [String] = []
        for (_, members) in byBurst {
            guard members.count > 1 else {
                // Lone burst-marked assets: still surface as clutter candidates except favorites.
                ids.append(contentsOf: members.filter { !$0.isFavorite }.map(\.id))
                continue
            }
            let keep = members.first(where: \.isFavorite)?.id
                ?? members.max(by: { $0.byteSize < $1.byteSize })?.id
            ids.append(contentsOf: members.map(\.id).filter { $0 != keep })
        }
        return ids
    }
}
