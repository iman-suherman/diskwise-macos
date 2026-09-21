package net.suherman.diskwise.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import net.suherman.diskwise.android.data.BucketSummary
import net.suherman.diskwise.android.data.MediaAsset
import net.suherman.diskwise.android.ui.DiskWiseViewModel
import net.suherman.diskwise.android.ui.screens.BucketScreen
import net.suherman.diskwise.android.ui.screens.ConfirmScreen
import net.suherman.diskwise.android.ui.screens.DashboardScreen
import net.suherman.diskwise.android.ui.screens.PermissionScreen
import net.suherman.diskwise.android.ui.screens.PreviewScreen
import net.suherman.diskwise.android.ui.theme.DiskWiseTheme

class MainActivity : ComponentActivity() {
    private val viewModel: DiskWiseViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DiskWiseTheme {
                DiskWiseApp(viewModel = viewModel)
            }
        }
    }
}

@Composable
fun DiskWiseApp(viewModel: DiskWiseViewModel) {
    val state by viewModel.state.collectAsState()
    val navController = rememberNavController()
    var pendingPreview by remember { mutableStateOf<MediaAsset?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        viewModel.refreshAuth()
        if (viewModel.state.value.auth.canReadLibrary) {
            viewModel.scan()
        }
    }

    val trashLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        viewModel.onTrashResult(result.resultCode)
        if (result.resultCode == DiskWiseViewModel.CleanupResult.OK) {
            navController.popBackStack("dashboard", inclusive = false)
            pendingPreview = null
        }
    }

    LaunchedEffect(state.pendingTrashRequest) {
        val request = state.pendingTrashRequest ?: return@LaunchedEffect
        trashLauncher.launch(request)
        viewModel.clearPendingTrash()
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshAuth()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
    }

    LaunchedEffect(state.auth.canReadLibrary) {
        if (state.auth.canReadLibrary && state.report.totalAssets == 0 && !state.isScanning) {
            viewModel.scan()
        }
    }

    if (state.errorMessage != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearError() },
            confirmButton = {
                TextButton(onClick = { viewModel.clearError() }) { Text("OK") }
            },
            title = { Text("Something went wrong") },
            text = { Text(state.errorMessage.orEmpty()) }
        )
    }

    val start = if (state.auth.canReadLibrary) "dashboard" else "permission"

    NavHost(
        navController = navController,
        startDestination = start,
        modifier = Modifier.fillMaxSize()
    ) {
        composable("permission") {
            PermissionScreen(
                auth = state.auth,
                onRequestAccess = {
                    permissionLauncher.launch(viewModel.requiredPermissions())
                },
                onOpenSettings = { viewModel.openAppSettings() }
            )
            LaunchedEffect(state.auth.canReadLibrary) {
                if (state.auth.canReadLibrary) {
                    navController.navigate("dashboard") {
                        popUpTo("permission") { inclusive = true }
                    }
                }
            }
        }
        composable("dashboard") {
            if (!state.auth.canReadLibrary) {
                LaunchedEffect(Unit) {
                    navController.navigate("permission") {
                        popUpTo("dashboard") { inclusive = true }
                    }
                }
            }
            DashboardScreen(
                state = state,
                onRescan = { viewModel.scan() },
                onOpenBucket = { summary ->
                    viewModel.applyDefaultSelection(summary)
                    navController.navigate("bucket/${summary.bucket.name}")
                },
                onOpenRecommendation = { rec ->
                    val summary = state.report.buckets.firstOrNull { it.bucket == rec.bucket }
                        ?: BucketSummary(rec.bucket, rec.assetIds, rec.estimatedSavings)
                    viewModel.applyDefaultSelection(summary)
                    navController.navigate("bucket/${summary.bucket.name}")
                }
            )
        }
        composable(
            route = "bucket/{bucket}",
            arguments = listOf(navArgument("bucket") { type = NavType.StringType })
        ) { entry ->
            val name = entry.arguments?.getString("bucket").orEmpty()
            val summary = state.report.buckets.firstOrNull { it.bucket.name == name }
            if (summary == null) {
                LaunchedEffect(Unit) { navController.popBackStack() }
                return@composable
            }
            BucketScreen(
                summary = summary,
                state = state,
                onBack = { navController.popBackStack() },
                onToggle = { viewModel.toggleSelection(it) },
                onKeepAsset = { id, group -> viewModel.keepAsset(id, group) },
                onPreview = { asset ->
                    pendingPreview = asset
                    navController.navigate("preview/${asset.id}")
                },
                onReview = { navController.navigate("confirm") }
            )
        }
        composable("confirm") {
            ConfirmScreen(
                state = state,
                onBack = { navController.popBackStack() },
                onConfirm = { viewModel.prepareTrashForSelection() }
            )
        }
        composable(
            route = "preview/{id}",
            arguments = listOf(navArgument("id") { type = NavType.LongType })
        ) { entry ->
            val id = entry.arguments?.getLong("id") ?: return@composable
            val asset = state.assetsById[id] ?: pendingPreview
            if (asset == null) {
                LaunchedEffect(Unit) { navController.popBackStack() }
                return@composable
            }
            PreviewScreen(
                asset = asset,
                onBack = { navController.popBackStack() },
                onDelete = { viewModel.prepareTrashForSingle(asset.id) }
            )
        }
    }
}
