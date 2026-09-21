package net.suherman.diskwise.android.data

import android.content.Context

class MediaConsultant(context: Context) {
    private val indexer = MediaStoreIndexer(context)
    private val insightEngine = InsightEngine()
    val cleanup = CleanupEngine(context)

    fun authorizationStatus(): MediaAuthStatus = indexer.authorizationStatus()

    fun requiredPermissions(): Array<String> = indexer.requiredPermissions()

    suspend fun scan(onProgress: (ScanProgress) -> Unit = {}): Pair<List<MediaAsset>, LibraryReport> {
        onProgress(ScanProgress("Scanning library", 0))
        val assets = indexer.indexLibrary(onProgress)
        onProgress(ScanProgress("Analyzing", assets.size, assets.size))
        val report = insightEngine.analyze(assets)
        onProgress(ScanProgress("Done", assets.size, assets.size))
        return assets to report
    }
}
