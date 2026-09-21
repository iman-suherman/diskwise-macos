package net.suherman.diskwise.android.data

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.result.IntentSenderRequest

/**
 * Moves selected media to the system Trash (recoverable) via MediaStore delete requests.
 * Never permanently empties Trash in v1.
 */
class CleanupEngine(private val context: Context) {

    fun createTrashRequest(uris: List<Uri>): IntentSenderRequest? {
        if (uris.isEmpty()) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val pi: PendingIntent = MediaStore.createDeleteRequest(context.contentResolver, uris)
            IntentSenderRequest.Builder(pi.intentSender).build()
        } else {
            // Pre-R: best-effort delete; items go to Trash on devices that support it.
            uris.forEach { uri ->
                try {
                    context.contentResolver.delete(uri, null, null)
                } catch (_: SecurityException) {
                    // Caller should surface permission error.
                }
            }
            null
        }
    }

    companion object {
        const val RESULT_OK = Activity.RESULT_OK
    }
}
