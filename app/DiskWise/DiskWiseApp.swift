import SwiftUI
import AppKit
import DiskScannerKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        FullDiskAccess.registerForFullDiskAccess()
        MenuBarMonitorController.unregisterLegacyLoginItemIfNeeded()

        DispatchQueue.main.async {
            _ = SparkleUpdaterController.shared
        }

        let icon: NSImage? = {
            if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: icnsURL) {
                return image
            }
            return NSImage(named: NSImage.applicationIconName)
        }()

        if let icon {
            NSApp.applicationIconImage = icon
        }

        MenuBarStatusItemController.shared.syncFreeSpaceVolumes(
            enabledPaths: AppSettings.shared.menuBarFreeSpaceVolumePaths
        )
        SystemVolumeMonitor.shared.refresh()
        MenuBarMonitorController.syncMenuBarItems(settings: AppSettings.shared)
        DockVisibilityController.apply(hidden: AppSettings.shared.hideFromDock)

        MemoryInsightNotificationService.shared.prepare()
        MemoryAnalyzerMonitor.shared.startIfNeeded(settings: AppSettings.shared)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppViewModel.current?.checkForUpdatesWhenEligible()
        }
    }
}

@main
struct DiskWiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appSettings = AppSettings.shared

    @SceneBuilder
    var body: some Scene {
        mainWindow
        settingsScene
    }

    private var mainWindow: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(appSettings)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About DiskWise") {
                    viewModel.showAbout = true
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }
            }
            CommandMenu("View") {
                ForEach(SystemVolumeMonitor.shared.volumes) { volume in
                    Toggle(
                        "Show \(volume.name) Free Space in Menu Bar",
                        isOn: Binding(
                            get: { appSettings.isMenuBarFreeSpaceVisible(for: volume.mountPath) },
                            set: { appSettings.setMenuBarFreeSpaceVisible(for: volume.mountPath, visible: $0) }
                        )
                    )
                }
                Toggle(
                    "Show Health Score in Menu Bar",
                    isOn: Binding(
                        get: { appSettings.showMenuBarHealthScore },
                        set: { appSettings.setMenuBarHealthScoreVisible($0) }
                    )
                )
            }
            CommandGroup(replacing: .help) {
                Button("Activity Log…") {
                    viewModel.showActivityLog = true
                }
            }
        }
    }

    private var settingsScene: some Scene {
        Settings {
            AppSettingsView(settings: appSettings)
                .onChange(of: appSettings.aiProviderPreference) { _, _ in
                    viewModel.refreshAIConfiguration()
                }
                .onChange(of: appSettings.enableOllamaDevMode) { _, _ in
                    viewModel.refreshAIConfiguration()
                }
                .onChange(of: appSettings.ollamaBaseURL) { _, _ in
                    viewModel.refreshAIConfiguration()
                }
                .onChange(of: appSettings.ollamaModel) { _, _ in
                    viewModel.refreshAIConfiguration()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var volumeMonitor = SystemVolumeMonitor.shared
    @ObservedObject private var healthMonitor = SystemHealthMonitor.shared

    var body: some View {
        ZStack {
            Group {
                if viewModel.isMainContentReady {
                    NavigationSplitView {
                        sidebar
                            .navigationTitle("DiskWise")
                            .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
                    } detail: {
                        detailContent
                            .toolbar {
                                launchToolbarContent
                            }
                    }
                } else {
                    Color(nsColor: .windowBackgroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .blur(radius: viewModel.isStartingUp || viewModel.isRebuildingIndex || viewModel.showPythonSetupPrompt || viewModel.showFullDiskAccessPrompt || viewModel.showWhatsNewTour || viewModel.showIndexRebuildPrompt || viewModel.showSavedScanPrompt || viewModel.showScanModePrompt ? 8 : 0)
            .allowsHitTesting(!viewModel.isStartingUp && !viewModel.isRebuildingIndex && !viewModel.showPythonSetupPrompt && !viewModel.showFullDiskAccessPrompt && !viewModel.showWhatsNewTour && !viewModel.showIndexRebuildPrompt && !viewModel.showSavedScanPrompt && !viewModel.showScanModePrompt)

            if viewModel.isStartingUp {
                StartupSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    isPostUpgrade: viewModel.isPostUpgradeStartup,
                    migratesScanFormat: viewModel.startupMigratesScanFormat,
                    prewarmsSavedScan: viewModel.startupPrewarmsSavedScan,
                    profilesSystemHealth: viewModel.startupProfilesSystemHealth,
                    includesAIInsights: viewModel.startupIncludesAIInsights,
                    currentMessage: viewModel.startupMessage,
                    highlightMessage: viewModel.startupMessageHighlight,
                    completedSteps: viewModel.startupCompletedSteps,
                    activeStep: viewModel.startupActiveStep,
                    showSkipPrewarm: viewModel.showStartupPrewarmSkip,
                    onSkipPrewarm: { viewModel.cancelStartupPrewarm() }
                )
            }

            if viewModel.showIndexRebuildPrompt {
                IndexRebuildOverlay(
                    version: AppSettings.currentAppVersion,
                    onRebuild: { viewModel.dismissIndexRebuildPrompt(rebuildNow: true) },
                    onSkip: { viewModel.dismissIndexRebuildPrompt(rebuildNow: false) }
                )
            }

            if viewModel.isRebuildingIndex {
                IndexRebuildProgressOverlay(
                    version: AppSettings.currentAppVersion,
                    volumeName: viewModel.selectedVolume?.name ?? viewModel.mountedVolumes.first?.name,
                    currentMessage: viewModel.indexRebuildMessage,
                    completedSteps: viewModel.indexRebuildCompletedSteps,
                    activeStep: viewModel.indexRebuildActiveStep,
                    scanProgress: viewModel.scanProgress
                )
            }

            if viewModel.showSavedScanPrompt, let volume = viewModel.selectedVolume {
                SavedScanPromptOverlay(
                    volumeName: volume.name,
                    onLoadSaved: { viewModel.dismissSavedScanPrompt(loadSaved: true, rebuild: false) },
                    onRebuild: { viewModel.dismissSavedScanPrompt(loadSaved: false, rebuild: true) },
                    onSkip: { viewModel.dismissSavedScanPrompt(loadSaved: false, rebuild: false) }
                )
            }

            if viewModel.showScanModePrompt, let volume = viewModel.selectedVolume {
                ScanModePromptOverlay(
                    volumeName: volume.name,
                    onFastScan: { viewModel.startScan(with: .fast) },
                    onDeepScan: { viewModel.startScan(with: .deep) },
                    onCancel: { viewModel.dismissScanModePrompt() }
                )
            }

            if viewModel.showWhatsNewTour {
                ReleaseNotesSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    onOpenSettings: { openSettings() },
                    onContinue: { viewModel.finishWhatsNewTour() }
                )
            }

            if viewModel.showPythonSetupPrompt {
                PythonSetupGateOverlay(
                    step: viewModel.pythonSetupWizardStep,
                    onInstall: {
                        viewModel.runPythonInstallScript()
                    },
                    onDismiss: {
                        viewModel.dismissPythonSetupPrompt()
                    },
                    onCancelWaiting: {
                        viewModel.cancelPythonSetupWaiting()
                    }
                )
            }

            if viewModel.showFullDiskAccessPrompt {
                FullDiskAccessGateOverlay(
                    step: viewModel.fullDiskAccessWizardStep,
                    mountedVolumeCount: viewModel.mountedVolumes.count,
                    missingVolumePaths: viewModel.missingExternalVolumePaths,
                    onGrantAccess: {
                        viewModel.grantFullDiskAccess()
                    },
                    onDismiss: {
                        viewModel.dismissFullDiskAccessPrompt()
                    },
                    onCancelWaiting: {
                        viewModel.cancelFullDiskAccessWaiting()
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.isStartingUp)
        .animation(.easeInOut(duration: 0.22), value: viewModel.isRebuildingIndex)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showPythonSetupPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showFullDiskAccessPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showIndexRebuildPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showSavedScanPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showScanModePrompt)
        .onChange(of: viewModel.showPythonSetupPrompt) { _, isShowing in
            if !isShowing {
                viewModel.stopPythonPollingIfNeeded()
            }
        }
        .onChange(of: viewModel.showFullDiskAccessPrompt) { _, isShowing in
            if !isShowing {
                viewModel.stopPermissionPollingIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkPermissionOnAppActivation()
            viewModel.checkPythonOnAppActivation()
            viewModel.checkForUpdatesWhenEligible()
        }
        .sheet(isPresented: $viewModel.showActivityLog) {
            ActivityLogSheet(activityLog: viewModel.activityLog)
        }
        .sheet(isPresented: $viewModel.showAbout) {
            AboutView(onOpenSettings: { openSettings() })
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $appSettings.showMenuBarMonitorInstructions) {
            MenuBarMonitorInstructionSheet()
        }
    }

    @ToolbarContentBuilder
    private var launchToolbarContent: some ToolbarContent {
        if viewModel.selectedPane == .overview {
            ToolbarItem(placement: .principal) {
                volumePicker
            }
        } else {
            ToolbarItem(placement: .principal) {
                Label(viewModel.selectedPane.title, systemImage: viewModel.selectedPane.icon)
                    .font(.headline)
            }
        }

        ToolbarItem(placement: .status) {
            StatusBadge(
                message: viewModel.toolbarStatusMessage,
                kind: viewModel.statusKind,
                isAnimating: viewModel.isScanning || viewModel.isFindingDuplicates || viewModel.isAnalyzing,
                onRefresh: viewModel.statusKind == .error && viewModel.statusMessage.hasPrefix("Scan failed")
                    ? { viewModel.refreshFromError() }
                    : nil
            )
        }

        if viewModel.selectedPane == .overview, let volume = viewModel.selectedVolume {
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.isIndexed(volume) {
                    Button {
                        viewModel.scanSelectedVolume(mode: .fast)
                    } label: {
                        Label(
                            viewModel.isScanning
                                ? "Identifying…"
                                : (viewModel.isAnalyzing ? "Analyzing…" : "Rescan \(volume.name)"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(viewModel.isVolumeBusy(volume))

                    Button {
                        viewModel.scanSelectedVolume(mode: .deep)
                    } label: {
                        Label("Deep Scan", systemImage: "scope")
                    }
                    .disabled(viewModel.isVolumeBusy(volume))
                } else {
                    Button {
                        viewModel.presentScanModePrompt(for: volume)
                    } label: {
                        Label(
                            viewModel.isScanning ? "Identifying…" : "Scan \(volume.name)",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(viewModel.isVolumeBusy(volume))
                }

                Button {
                    viewModel.scanFolderOnSelectedVolume()
                } label: {
                    Label("Scan Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(viewModel.isVolumeBusy(volume))
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                SparkleUpdaterController.shared.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
            }
            .help("Check for Updates…")
        }
    }

    private var volumePicker: some View {
        Menu {
            if !viewModel.internalVolumes.isEmpty {
                Section("Internal SSD") {
                    ForEach(viewModel.internalVolumes) { volume in
                        volumeMenuButton(volume)
                    }
                }
            }
            if !viewModel.externalVolumes.isEmpty {
                Section("External Drives") {
                    ForEach(viewModel.externalVolumes) { volume in
                        volumeMenuButton(volume)
                    }
                }
            }
            if viewModel.mountedVolumes.isEmpty {
                Button("Grant Permission") {
                    viewModel.presentFullDiskAccessOverlay()
                }
            }
            Divider()
            Button {
                viewModel.refreshDrivesAfterPermissionChange()
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.selectedVolume?.isInternal == false ? "externaldrive.fill" : "internaldrive.fill")
                Text(viewModel.selectedVolume?.name ?? "Select Drive")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280)
        }
        .menuStyle(.borderlessButton)
    }

    private func volumeMenuButton(_ volume: MountedVolume) -> some View {
        Button {
            viewModel.selectedVolumePath = volume.mountPath
            viewModel.selectVolume(volume)
        } label: {
            HStack {
                Text(volume.name)
                Spacer()
                if viewModel.selectedVolumePath == volume.mountPath {
                    Image(systemName: "checkmark")
                }
                Text(DiskWiseFormatters.bytes.string(fromByteCount: volume.freeSize) + " free")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedPane {
        case .overview:
            VolumeDiskTabView()
        case .systemOptimization:
            SystemOptimizationView()
        case .maintenance:
            MaintenanceView()
        case .duplicates:
            DuplicatesView()
        case .ai:
            VolumeDiskTabView()
                .onAppear { viewModel.selectedVolumeTab = .aiAnalysis }
        }
    }

    private func healthScoreBadgeColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func menuBadge(for pane: DetailPane) -> some View {
        Group {
            switch pane {
            case .overview:
                if let volume = volumeMonitor.systemVolume {
                    SidebarDiskFreeSpaceBadge(volume: volume)
                }
            case .systemOptimization:
                if let score = healthMonitor.snapshot?.healthScore {
                    SidebarStackedScoreBadges(
                        healthScore: score,
                        healthColor: healthScoreBadgeColor
                    )
                }
            case .duplicates:
                if viewModel.duplicateGroups.count > 0 {
                    Text("\(viewModel.duplicateGroups.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                }
            default:
                EmptyView()
            }
        }
    }


    @ViewBuilder
    private func sidebarMenuRow<Trailing: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: icon)
            }
            Spacer(minLength: 4)
            trailing()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedPane) {
            if viewModel.shouldShowFullDiskAccessBanner {
                Section {
                    FullDiskAccessBanner(
                        missingVolumePaths: viewModel.missingExternalVolumePaths,
                        onGrantAccess: {
                            viewModel.presentFullDiskAccessOverlay()
                        }
                    )
                }
            }

            if viewModel.shouldShowPythonSetupBanner {
                Section {
                    PythonSetupBanner {
                        viewModel.presentPythonSetupOverlay()
                    }
                }
            }

            Section {
                ForEach(viewModel.orderedMenuPanes) { pane in
                    sidebarMenuRow(
                        title: pane.title,
                        subtitle: pane.subtitle,
                        icon: pane.icon,
                        trailing: { menuBadge(for: pane) }
                    )
                    .tag(pane)
                }
                .onMove(perform: viewModel.moveMenuPane)
            } header: {
                Text("Menu")
            }

            Section {
                Button {
                    viewModel.showActivityLog = true
                } label: {
                    sidebarMenuRow(
                        title: "Activity Log",
                        subtitle: "Scan, cleanup, and system events",
                        icon: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.borderless)

                if viewModel.hasScanData {
                    Button {
                        viewModel.openDuplicatesPane()
                        if !viewModel.isFindingDuplicates && viewModel.duplicateGroups.isEmpty {
                            viewModel.scanForDuplicates()
                        }
                    } label: {
                        sidebarMenuRow(
                            title: viewModel.isFindingDuplicates
                                ? "Finding Duplicates…"
                                : "Find Duplicates",
                            subtitle: viewModel.totalDuplicateSavings > 0
                                ? "\(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.totalDuplicateSavings)) reclaimable"
                                : "Scan indexed files for duplicate copies",
                            icon: "doc.on.doc"
                        )
                    }
                    .buttonStyle(.borderless)
                }

                if viewModel.canEjectSelectedVolume, let volume = viewModel.selectedVolume {
                    Button {
                        viewModel.ejectSelectedVolume()
                    } label: {
                        sidebarMenuRow(
                            title: "Eject \(volume.name)",
                            subtitle: "Safely disconnect this external drive",
                            icon: "eject.fill"
                        )
                    }
                    .disabled(viewModel.isVolumeBusy(volume))
                    .buttonStyle(.borderless)
                }

                Button {
                    openSettings()
                } label: {
                    sidebarMenuRow(
                        title: "Settings",
                        subtitle: "Scan limits, AI provider, and preferences",
                        icon: "gearshape"
                    )
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Actions")
            }
        }
        .listStyle(.sidebar)
    }
}
