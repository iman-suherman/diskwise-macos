package net.suherman.diskwise.android.data

import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MediaStoreIndexer(private val context: Context) {

    fun authorizationStatus(): MediaAuthStatus {
        val images = hasPermission(imagePermission())
        val videos = hasPermission(videoPermission())
        return when {
            images && videos -> MediaAuthStatus.Granted
            images || videos -> MediaAuthStatus.Partial
            else -> MediaAuthStatus.Denied
        }
    }

    fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                android.Manifest.permission.READ_MEDIA_IMAGES,
                android.Manifest.permission.READ_MEDIA_VIDEO
            )
        } else {
            arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun imagePermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_IMAGES
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun videoPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            android.Manifest.permission.READ_MEDIA_VIDEO
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    suspend fun indexLibrary(
        onProgress: (ScanProgress) -> Unit = {}
    ): List<MediaAsset> = withContext(Dispatchers.IO) {
        val results = mutableListOf<MediaAsset>()
        onProgress(ScanProgress("Indexing images", 0))
        results += queryCollection(
            collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            mediaType = MediaType.Image,
            onProgress = onProgress
        )
        onProgress(ScanProgress("Indexing videos", results.size))
        results += queryCollection(
            collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            mediaType = MediaType.Video,
            onProgress = onProgress
        )
        onProgress(ScanProgress("Indexed", results.size, results.size))
        results
    }

    private fun queryCollection(
        collection: Uri,
        mediaType: MediaType,
        onProgress: (ScanProgress) -> Unit
    ): List<MediaAsset> {
        val assets = mutableListOf<MediaAsset>()
        val projection = buildList {
            add(MediaStore.MediaColumns._ID)
            add(MediaStore.MediaColumns.DISPLAY_NAME)
            add(MediaStore.MediaColumns.SIZE)
            add(MediaStore.MediaColumns.WIDTH)
            add(MediaStore.MediaColumns.HEIGHT)
            add(MediaStore.MediaColumns.DATE_ADDED)
            add(MediaStore.MediaColumns.DATE_TAKEN)
            add(MediaStore.MediaColumns.RELATIVE_PATH)
            if (mediaType == MediaType.Video) {
                add(MediaStore.Video.Media.DURATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(MediaStore.MediaColumns.IS_FAVORITE)
            }
        }.toTypedArray()

        val sortOrder = "${MediaStore.MediaColumns.DATE_ADDED} DESC"
        context.contentResolver.query(collection, projection, null, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val widthCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
            val heightCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
            val addedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val takenCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
            val durationCol = if (mediaType == MediaType.Video) {
                cursor.getColumnIndex(MediaStore.Video.Media.DURATION)
            } else {
                -1
            }
            val favoriteCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                cursor.getColumnIndex(MediaStore.MediaColumns.IS_FAVORITE)
            } else {
                -1
            }

            var count = 0
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id)
                val size = cursor.getLong(sizeCol).coerceAtLeast(0)
                val width = cursor.getInt(widthCol).coerceAtLeast(0)
                val height = cursor.getInt(heightCol).coerceAtLeast(0)
                val dateAddedSec = cursor.getLong(addedCol)
                val dateTaken = cursor.getLong(takenCol).takeIf { it > 0 }
                val duration = if (durationCol >= 0) cursor.getLong(durationCol).coerceAtLeast(0) else 0L
                val favorite = favoriteCol >= 0 && cursor.getInt(favoriteCol) != 0

                assets += MediaAsset(
                    id = id,
                    uri = uri,
                    mediaType = mediaType,
                    byteSize = size,
                    pixelWidth = width,
                    pixelHeight = height,
                    durationMs = duration,
                    dateAddedMs = dateAddedSec * 1000L,
                    dateTakenMs = dateTaken,
                    displayName = cursor.getString(nameCol),
                    relativePath = cursor.getString(pathCol),
                    isFavorite = favorite
                )
                count++
                if (count % 250 == 0) {
                    onProgress(
                        ScanProgress(
                            phase = if (mediaType == MediaType.Video) "Indexing videos" else "Indexing images",
                            scanned = count
                        )
                    )
                }
            }
        }
        return assets
    }
}
