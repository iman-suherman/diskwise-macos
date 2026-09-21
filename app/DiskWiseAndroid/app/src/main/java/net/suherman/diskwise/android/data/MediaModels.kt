package net.suherman.diskwise.android.data

import android.net.Uri

enum class MediaAuthStatus {
    NotDetermined,
    Denied,
    Granted,
    Partial;

    val canReadLibrary: Boolean
        get() = this == Granted || this == Partial
}

enum class MediaType {
    Image,
    Video,
    Unknown
}

enum class ClutterBucket(
    val title: String,
    val subtitle: String
) {
    ExactDuplicates(
        title = "Exact Duplicates",
        subtitle = "Same size and dimensions — keep one copy"
    ),
    Screenshots(
        title = "Screenshots",
        subtitle = "Screen captures — preview before cleaning"
    ),
    LargeVideos(
        title = "Large Videos",
        subtitle = "Videos over 100 MB"
    ),
    OldMedia(
        title = "Older Media",
        subtitle = "Items older than two years"
    )
}

data class MediaAsset(
    val id: Long,
    val uri: Uri,
    val mediaType: MediaType,
    val byteSize: Long,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val durationMs: Long,
    val dateAddedMs: Long,
    val dateTakenMs: Long?,
    val displayName: String?,
    val relativePath: String?,
    val isFavorite: Boolean = false
) {
    val isVideo: Boolean get() = mediaType == MediaType.Video

    val isScreenshot: Boolean
        get() {
            val name = displayName?.lowercase().orEmpty()
            val path = relativePath?.lowercase().orEmpty()
            return path.contains("screenshot") ||
                name.startsWith("screenshot") ||
                name.startsWith("screen_") ||
                path.contains("screenshots")
        }

    val creationMs: Long
        get() = dateTakenMs?.takeIf { it > 0 } ?: dateAddedMs

    val exactFingerprint: String
        get() = "${mediaType.name}_${byteSize}_${pixelWidth}x${pixelHeight}_$durationMs"
}

data class DuplicateGroup(
    val id: String,
    val fingerprint: String,
    val assets: List<MediaAsset>
) {
    val totalSize: Long = assets.sumOf { it.byteSize }
    val reclaimableSize: Long = assets.sortedByDescending { it.byteSize }.drop(1).sumOf { it.byteSize }

    val suggestedKeepId: Long
        get() = assets.firstOrNull { it.isFavorite }?.id
            ?: assets.maxByOrNull { it.byteSize }?.id
            ?: assets.first().id

    val suggestedCleanupIds: List<Long>
        get() = assets.map { it.id }.filter { it != suggestedKeepId }
}

data class BucketSummary(
    val bucket: ClutterBucket,
    val assetIds: List<Long>,
    val reclaimableBytes: Long
) {
    val itemCount: Int get() = assetIds.size
}

data class Recommendation(
    val bucket: ClutterBucket,
    val title: String,
    val detail: String,
    val estimatedSavings: Long,
    val assetIds: List<Long>
)

data class LibraryReport(
    val scannedAtMs: Long = System.currentTimeMillis(),
    val totalAssets: Int = 0,
    val totalBytes: Long = 0,
    val buckets: List<BucketSummary> = emptyList(),
    val exactDuplicateGroups: List<DuplicateGroup> = emptyList(),
    val recommendations: List<Recommendation> = emptyList()
) {
    val reclaimableBytes: Long get() = buckets.sumOf { it.reclaimableBytes }

    companion object {
        val Empty = LibraryReport()
    }
}

data class ScanProgress(
    val phase: String,
    val scanned: Int,
    val totalHint: Int? = null
)

object ByteFormat {
    fun format(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unit = -1
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024.0
            unit++
        }
        return if (value >= 100 || unit == 0) {
            String.format("%.0f %s", value, units[unit])
        } else {
            String.format("%.1f %s", value, units[unit])
        }
    }
}
