package net.suherman.diskwise.android.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.result.IntentSenderRequest
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import net.suherman.diskwise.android.data.BucketSummary
import net.suherman.diskwise.android.data.ByteFormat
import net.suherman.diskwise.android.data.ClutterBucket
import net.suherman.diskwise.android.data.DuplicateGroup
import net.suherman.diskwise.android.data.LibraryReport
import net.suherman.diskwise.android.data.MediaAsset
import net.suherman.diskwise.android.data.MediaAuthStatus
import net.suherman.diskwise.android.data.MediaConsultant
import net.suherman.diskwise.android.data.ScanProgress

data class UiState(
    val auth: MediaAuthStatus = MediaAuthStatus.Denied,
    val isScanning: Boolean = false,
    val isCleaning: Boolean = false,
    val scanProgress: ScanProgress? = null,
    val report: LibraryReport = LibraryReport.Empty,
    val assetsById: Map<Long, MediaAsset> = emptyMap(),
    val selectedIds: Set<Long> = emptySet(),
    val selectionContext: String? = null,
    val errorMessage: String? = null,
    val lastCleanupCount: Int? = null,
    val pendingTrashRequest: IntentSenderRequest? = null
)

class DiskWiseViewModel(application: Application) : AndroidViewModel(application) {
    private val consultant = MediaConsultant(application)

    private val _state = MutableStateFlow(UiState(auth = consultant.authorizationStatus()))
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun requiredPermissions(): Array<String> = consultant.requiredPermissions()

    fun refreshAuth() {
        _state.update { it.copy(auth = consultant.authorizationStatus()) }
    }

    fun openAppSettings() {
        val context = getApplication<Application>()
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null)
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun scan() {
        if (!_state.value.auth.canReadLibrary) return
        viewModelScope.launch {
            _state.update {
                it.copy(isScanning = true, errorMessage = null, scanProgress = ScanProgress("Starting", 0))
            }
            try {
                val (assets, report) = consultant.scan { progress ->
                    _state.update { s -> s.copy(scanProgress = progress) }
                }
                _state.update {
                    it.copy(
                        isScanning = false,
                        scanProgress = null,
                        report = report,
                        assetsById = assets.associateBy { asset -> asset.id },
                        selectedIds = emptySet(),
                        selectionContext = null
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isScanning = false,
                        scanProgress = null,
                        errorMessage = e.message ?: "Scan failed"
                    )
                }
            }
        }
    }

    fun clearError() {
        _state.update { it.copy(errorMessage = null) }
    }

    fun applyDefaultSelection(summary: BucketSummary) {
        val contextKey = summary.bucket.name
        val current = _state.value
        if (current.selectionContext == contextKey) return

        val defaults = when (summary.bucket) {
            ClutterBucket.ExactDuplicates -> {
                current.report.exactDuplicateGroups.flatMap { it.suggestedCleanupIds }.toSet()
            }
            else -> summary.assetIds.toSet()
        }
        _state.update {
            it.copy(selectedIds = defaults, selectionContext = contextKey)
        }
    }

    fun toggleSelection(id: Long) {
        _state.update { state ->
            val next = state.selectedIds.toMutableSet()
            if (!next.add(id)) next.remove(id)
            state.copy(selectedIds = next)
        }
    }

    fun keepThis(group: DuplicateGroup) {
        _state.update { state ->
            val next = state.selectedIds.toMutableSet()
            group.assets.forEach { asset ->
                if (asset.id == group.suggestedKeepId) {
                    next.remove(asset.id)
                } else {
                    next.add(asset.id)
                }
            }
            // If user picked a different keep, treat tapped keep as keep:
            state.copy(selectedIds = next)
        }
    }

    fun keepAsset(id: Long, group: DuplicateGroup) {
        _state.update { state ->
            val next = state.selectedIds.toMutableSet()
            group.assets.forEach { asset ->
                if (asset.id == id) next.remove(asset.id) else next.add(asset.id)
            }
            state.copy(selectedIds = next)
        }
    }

    fun selectedBytes(): Long {
        val state = _state.value
        return state.selectedIds.sumOf { id -> state.assetsById[id]?.byteSize ?: 0L }
    }

    fun formatSelected(): String = ByteFormat.format(selectedBytes())

    fun prepareTrashForSelection() {
        val state = _state.value
        val uris = state.selectedIds.mapNotNull { state.assetsById[it]?.uri }
        if (uris.isEmpty()) {
            _state.update { it.copy(errorMessage = "Select at least one item to clean up.") }
            return
        }
        val request = consultant.cleanup.createTrashRequest(uris)
        if (request == null) {
            // Pre-R path already deleted; refresh.
            _state.update {
                it.copy(
                    lastCleanupCount = uris.size,
                    selectedIds = emptySet(),
                    isCleaning = false
                )
            }
            scan()
        } else {
            _state.update { it.copy(pendingTrashRequest = request, isCleaning = true) }
        }
    }

    fun prepareTrashForSingle(id: Long) {
        val asset = _state.value.assetsById[id] ?: return
        val request = consultant.cleanup.createTrashRequest(listOf(asset.uri))
        if (request == null) {
            _state.update { it.copy(lastCleanupCount = 1, selectedIds = it.selectedIds - id) }
            scan()
        } else {
            _state.update {
                it.copy(
                    pendingTrashRequest = request,
                    isCleaning = true,
                    selectedIds = setOf(id)
                )
            }
        }
    }

    fun onTrashResult(resultCode: Int) {
        val count = _state.value.selectedIds.size
        _state.update {
            it.copy(
                pendingTrashRequest = null,
                isCleaning = false,
                lastCleanupCount = if (resultCode == CleanupResult.OK) count else null,
                selectedIds = if (resultCode == CleanupResult.OK) emptySet() else it.selectedIds,
                errorMessage = if (resultCode == CleanupResult.OK) null else "Cleanup was cancelled."
            )
        }
        if (resultCode == CleanupResult.OK) {
            scan()
        }
    }

    fun clearPendingTrash() {
        _state.update { it.copy(pendingTrashRequest = null) }
    }

    object CleanupResult {
        const val OK = android.app.Activity.RESULT_OK
    }
}
