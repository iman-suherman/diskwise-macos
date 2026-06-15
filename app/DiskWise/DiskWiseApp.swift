import SwiftUI
import AppKit
import DiskScannerKit
import MaintenanceKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        FullDiskAccess.registerForFullDiskAccess()
        MenuBarMonitorController.unregisterLegacyLoginItemIfNeeded()

        DispatchQueue.main.async {
            _ = SparkleUpdaterController.shared
        }

        let icon: NSImage? = AppBrandIcon.loadImage() ?? {
            if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: icnsURL) {
                return image
            }
            return NSImage(named: NSImage.applicationIconName)
        }()

        if let icon {
            icon.isTemplate = false
            NSApp.applicationIconImage = icon
        }

        MenuBarStatusItemController.shared.syncFreeSpaceVolumes(
            enabledPaths: AppSettings.shared.menuBarFreeSpaceVolumePaths
        )
        SystemVolumeMonitor.shared.refresh()
        MenuBarMonitorController.syncMenuBarItems(settings: AppSettings.shared)
        DockVisibilityController.apply(hidden: AppSettings.shared.hideFromDock)
        DockScanAnimator.shared.stop()

        MemoryInsightNotificationService.shared.prepare()
        DiskSpaceNotificationService.shared.prepare()
        SystemHealthNotificationService.shared.prepare()
        MemoryAnalyzerMonitor.shared.startIfNeeded(settings: AppSettings.shared)
        ScanScheduleService.shared.start()

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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    viewModel.openSettingsPane()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Activity Log…") {
                    viewModel.openActivityLogPane()
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var volumeMonitor = SystemVolumeMonitor.shared
    @ObservedObject private var healthMonitor = SystemHealthMonitor.shared

    var body: some View {
        ZStack {
            Group {
                if viewModel.isMainContentReady {
                    NavigationSplitView {
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                AppBrandIcon(size: 32, showsShadow: false)
                                Text("DiskWise")
                                    .font(.title2.bold())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 6)

                            sidebar
                        }
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
                    onOpenSettings: { viewModel.openSettingsPane() },
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
        .sheet(isPresented: $viewModel.showAbout) {
            AboutView(onOpenSettings: { viewModel.openSettingsPane() })
                .environmentObject(appSettings)
        }
        .sheet(isPresented: $appSettings.showMenuBarMonitorInstructions) {
            MenuBarMonitorInstructionSheet()
        }
    }

    @ToolbarContentBuilder
    private var launchToolbarContent: some ToolbarContent {
        if case .pane(let pane) = viewModel.sidebarSelection, pane != .overview {
            ToolbarItem(placement: .principal) {
                Label(pane.title, systemImage: pane.icon)
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

        ToolbarItem(placement: .automatic) {
            Button {
                SparkleUpdaterController.shared.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.sidebarSelection {
        case .pane(.overview):
            VolumeDiskTabView()
        case .pane(.systemOptimization):
            SystemOptimizationView()
        case .pane(.startupApps):
            StartupAppsView()
        case .pane(.duplicates):
            DuplicatesView()
        case .pane(.cleanMyMac):
            MaintenanceSectionView(section: .clean)
                .id(DetailPane.cleanMyMac)
        case .pane(.systemCleanup):
            MaintenanceSectionView(section: .system)
                .id(DetailPane.systemCleanup)
        case .pane(.ai):
            VolumeDiskTabView()
                .onAppear { viewModel.selectedVolumeTab = .insights }
        case .pane(.activityLog):
            ActivityLogView(activityLog: viewModel.activityLog, embeddedInPanel: true)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .pane(.settings):
            AppSettingsView(settings: appSettings, embeddedInPanel: true)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
            trailing()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.sidebarSelection) {
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
                    .tag(SidebarSelection.pane(pane))
                }
                .onMove(perform: viewModel.moveMenuPane)
            } header: {
                Text("Menu")
            }

            if viewModel.canEjectSelectedVolume, let volume = viewModel.selectedVolume {
                Section {
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
            }

            Section {
                ForEach(DetailPane.utilityMenuPanes) { pane in
                    sidebarMenuRow(
                        title: pane.title,
                        subtitle: pane.subtitle,
                        icon: pane.icon
                    )
                    .tag(SidebarSelection.pane(pane))
                }
            } header: {
                Text("General")
            }
        }
        .listStyle(.sidebar)
        .onChange(of: viewModel.sidebarSelection) { _, selection in
            if case .pane(let pane) = selection, let section = pane.maintenanceSection {
                viewModel.prepareMaintenanceSection(section)
            }
        }
    }
}
