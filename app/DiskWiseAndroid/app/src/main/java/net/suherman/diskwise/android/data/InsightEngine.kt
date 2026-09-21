package net.suherman.diskwise.android.data

class InsightEngine(
    private val duplicateEngine: DuplicateEngine = DuplicateEngine(),
    private val largeVideoBytes: Long = 100L * 1024 * 1024,
    private val oldMediaAgeMs: Long = 365L * 2 * 24 * 60 * 60 * 1000,
    private val referenceMs: Long = System.currentTimeMillis()
) {
    fun analyze(assets: List<MediaAsset>): LibraryReport {
        val exactGroups = duplicateEngine.findExactDuplicates(assets)
        val claimed = mutableSetOf<Long>()
        val buckets = mutableListOf<BucketSummary>()
        val recommendations = mutableListOf<Recommendation>()

        fun append(
            bucket: ClutterBucket,
            ids: List<Long>,
            reclaimable: Long,
            title: String,
            detail: String
        ) {
            val unique = ids.filter { claimed.add(it) }
            if (unique.isEmpty()) return
            val bytes = if (reclaimable > 0) {
                reclaimable
            } else {
                assets.filter { it.id in unique }.sumOf { it.byteSize }
            }
            buckets += BucketSummary(bucket, unique, bytes)
            recommendations += Recommendation(bucket, title, detail, bytes, unique)
        }

        val exactCleanup = exactGroups.flatMap { it.suggestedCleanupIds }
        val exactReclaimable = exactGroups.sumOf { it.reclaimableSize }
        append(
            ClutterBucket.ExactDuplicates,
            exactCleanup,
            exactReclaimable,
            "Remove exact duplicates",
            "Keep one copy per group; extras go to Trash."
        )

        val screenshotIds = assets
            .filter { it.isScreenshot && it.id !in claimed }
            .map { it.id }
        append(
            ClutterBucket.Screenshots,
            screenshotIds,
            0,
            "Clean up screenshots",
            "Preview each item, then confirm before moving to Trash."
        )

        val largeVideoIds = assets
            .filter { it.isVideo && it.byteSize >= largeVideoBytes && it.id !in claimed }
            .sortedByDescending { it.byteSize }
            .map { it.id }
        append(
            ClutterBucket.LargeVideos,
            largeVideoIds,
            0,
            "Review large videos",
            "Videos over 100 MB — keep favorites, remove the rest."
        )

        val cutoff = referenceMs - oldMediaAgeMs
        val oldIds = assets
            .filter {
                it.creationMs in 1 until cutoff && !it.isFavorite && it.id !in claimed
            }
            .map { it.id }
        append(
            ClutterBucket.OldMedia,
            oldIds,
            0,
            "Review older media",
            "Items older than two years that are not marked favorite."
        )

        val orderedBuckets = ClutterBucket.entries.mapNotNull { kind ->
            buckets.firstOrNull { it.bucket == kind }
        }
        val orderedRecs = ClutterBucket.entries.mapNotNull { kind ->
            recommendations.firstOrNull { it.bucket == kind }
        }.sortedByDescending { it.estimatedSavings }

        return LibraryReport(
            totalAssets = assets.size,
            totalBytes = assets.sumOf { it.byteSize },
            buckets = orderedBuckets,
            exactDuplicateGroups = exactGroups,
            recommendations = orderedRecs
        )
    }
}
