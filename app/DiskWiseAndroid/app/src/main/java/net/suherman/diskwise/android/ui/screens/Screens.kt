package net.suherman.diskwise.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import net.suherman.diskwise.android.data.BucketSummary
import net.suherman.diskwise.android.data.ByteFormat
import net.suherman.diskwise.android.data.ClutterBucket
import net.suherman.diskwise.android.data.DuplicateGroup
import net.suherman.diskwise.android.data.MediaAsset
import net.suherman.diskwise.android.data.MediaAuthStatus
import net.suherman.diskwise.android.data.Recommendation
import net.suherman.diskwise.android.ui.UiState

@Composable
fun PermissionScreen(
    auth: MediaAuthStatus,
    onRequestAccess: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Filled.PhotoLibrary,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(64.dp)
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            text = "Photos storage consultant",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "DiskWise analyzes your gallery on this device, finds reclaimable space, and moves selected items to Trash — never permanently deletes in v1.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(28.dp))
        Button(
            onClick = onRequestAccess,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Continue")
        }
        if (auth == MediaAuthStatus.Denied) {
            TextButton(onClick = onOpenSettings) {
                Text("Open Settings")
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "All analysis stays on-device. Photo contents are not uploaded.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
            textAlign = TextAlign.Center
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    state: UiState,
    onRescan: () -> Unit,
    onOpenBucket: (BucketSummary) -> Unit,
    onOpenRecommendation: (Recommendation) -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("DiskWise") },
                actions = {
                    IconButton(
                        onClick = onRescan,
                        enabled = !state.isScanning && !state.isCleaning
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Rescan library")
                    }
                }
            )
        }
    ) { padding ->
        if (state.isScanning && state.report.totalAssets == 0) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(16.dp))
                Text(state.scanProgress?.phase ?: "Scanning…")
                state.scanProgress?.let { progress ->
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "${progress.scanned} items",
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primaryContainer
                        )
                    ) {
                        Column(modifier = Modifier.padding(20.dp)) {
                            Text(
                                text = "Reclaimable",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                            )
                            Text(
                                text = ByteFormat.format(state.report.reclaimableBytes),
                                style = MaterialTheme.typography.headlineLarge,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                            Text(
                                text = "${state.report.totalAssets} items · ${ByteFormat.format(state.report.totalBytes)} scanned",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                            )
                            if (state.isScanning) {
                                Spacer(modifier = Modifier.height(12.dp))
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            }
                            state.lastCleanupCount?.let { count ->
                                Spacer(modifier = Modifier.height(8.dp))
                                Text(
                                    text = "Moved $count item(s) to Trash. You can recover them from system Trash.",
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                    }
                }

                if (state.report.recommendations.isNotEmpty()) {
                    item {
                        Text(
                            text = "Recommended",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    items(
                        items = state.report.recommendations.take(3),
                        key = { it.bucket.name }
                    ) { rec ->
                        RecommendationCard(rec = rec, onClick = { onOpenRecommendation(rec) })
                    }
                }

                item {
                    Text(
                        text = "Buckets",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
                items(
                    items = state.report.buckets,
                    key = { it.bucket.name }
                ) { bucket ->
                    BucketRow(summary = bucket, onClick = { onOpenBucket(bucket) })
                }

                if (state.report.buckets.isEmpty() && !state.isScanning) {
                    item {
                        Text(
                            text = "No reclaimable clutter found yet. Rescan after adding photos, or grant full media access.",
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RecommendationCard(rec: Recommendation, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = rec.title, fontWeight = FontWeight.SemiBold)
            Text(
                text = rec.detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = ByteFormat.format(rec.estimatedSavings),
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun BucketRow(summary: BucketSummary, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = summary.bucket.title, fontWeight = FontWeight.SemiBold)
                Text(
                    text = "${summary.itemCount} items · ${summary.bucket.subtitle}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                )
            }
            Text(
                text = ByteFormat.format(summary.reclaimableBytes),
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BucketScreen(
    summary: BucketSummary,
    state: UiState,
    onBack: () -> Unit,
    onToggle: (Long) -> Unit,
    onKeepAsset: (Long, DuplicateGroup) -> Unit,
    onPreview: (MediaAsset) -> Unit,
    onReview: () -> Unit
) {
    val assets = summary.assetIds.mapNotNull { state.assetsById[it] }
    val groups = if (summary.bucket == ClutterBucket.ExactDuplicates) {
        state.report.exactDuplicateGroups
    } else {
        emptyList()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(summary.bucket.title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        bottomBar = {
            if (state.selectedIds.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("${state.selectedIds.size} selected")
                        Text(
                            text = ByteFormat.format(
                                state.selectedIds.sumOf { id -> state.assetsById[id]?.byteSize ?: 0L }
                            ),
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Medium
                        )
                    }
                    Button(onClick = onReview) { Text("Review") }
                }
            }
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text(
                    text = summary.bucket.subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                )
            }

            if (groups.isNotEmpty()) {
                items(items = groups, key = { it.id }) { group ->
                    DuplicateGroupCard(
                        group = group,
                        selectedIds = state.selectedIds,
                        onToggle = onToggle,
                        onKeep = onKeepAsset,
                        onPreview = onPreview
                    )
                }
            } else {
                items(items = assets, key = { it.id }) { asset ->
                    AssetRow(
                        asset = asset,
                        selected = asset.id in state.selectedIds,
                        onToggle = { onToggle(asset.id) },
                        onPreview = { onPreview(asset) }
                    )
                }
            }
        }
    }
}

@Composable
private fun DuplicateGroupCard(
    group: DuplicateGroup,
    selectedIds: Set<Long>,
    onToggle: (Long) -> Unit,
    onKeep: (Long, DuplicateGroup) -> Unit,
    onPreview: (MediaAsset) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Group · reclaim ${ByteFormat.format(group.reclaimableSize)}",
                style = MaterialTheme.typography.labelLarge
            )
            group.assets.forEach { asset ->
                AssetRow(
                    asset = asset,
                    selected = asset.id in selectedIds,
                    keepLabel = asset.id == group.suggestedKeepId,
                    onToggle = { onToggle(asset.id) },
                    onPreview = { onPreview(asset) },
                    onKeep = { onKeep(asset.id, group) }
                )
            }
        }
    }
}

@Composable
private fun AssetRow(
    asset: MediaAsset,
    selected: Boolean,
    keepLabel: Boolean = false,
    onToggle: () -> Unit,
    onPreview: () -> Unit,
    onKeep: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onPreview)
            .padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onToggle) {
            Icon(
                imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                contentDescription = if (selected) "Selected" else "Not selected",
                tint = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                }
            )
        }
        AsyncImage(
            model = asset.uri,
            contentDescription = asset.displayName,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = asset.displayName ?: "Media ${asset.id}",
                maxLines = 1,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = ByteFormat.format(asset.byteSize) + if (asset.isVideo) " · video" else "",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            if (keepLabel) {
                Text(
                    text = "Suggested keep",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
        if (onKeep != null) {
            TextButton(onClick = onKeep) { Text("Keep") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfirmScreen(
    state: UiState,
    onBack: () -> Unit,
    onConfirm: () -> Unit
) {
    val selected = state.selectedIds.mapNotNull { state.assetsById[it] }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Confirm cleanup") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
        ) {
            Text(
                text = "Move ${selected.size} item(s) (${ByteFormat.format(selected.sumOf { it.byteSize })}) to Trash?",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Items go to system Trash so you can recover them. DiskWise never empties Trash.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
            )
            Spacer(modifier = Modifier.height(16.dp))
            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(items = selected, key = { it.id }) { asset ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        AsyncImage(
                            model = asset.uri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(8.dp))
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(text = asset.displayName ?: "Media", maxLines = 1)
                            Text(
                                text = ByteFormat.format(asset.byteSize),
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                    }
                }
            }
            Button(
                onClick = onConfirm,
                enabled = selected.isNotEmpty() && !state.isCleaning,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.Delete, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Move to Trash")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreviewScreen(
    asset: MediaAsset,
    onBack: () -> Unit,
    onDelete: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(asset.displayName ?: "Preview") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Filled.Delete, contentDescription = "Move to Trash")
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.surface),
            contentAlignment = Alignment.Center
        ) {
            val ratio = if (asset.pixelWidth > 0 && asset.pixelHeight > 0) {
                asset.pixelWidth.toFloat() / asset.pixelHeight.toFloat()
            } else {
                1f
            }
            AsyncImage(
                model = asset.uri,
                contentDescription = asset.displayName,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(ratio)
                    .padding(8.dp)
            )
        }
    }
}
