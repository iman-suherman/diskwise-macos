import SwiftUI
import AppKit
import DiskScannerKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        FullDiskAccess.registerForFullDiskAccess()

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
    }
}

@main
struct DiskWiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(appSettings)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.automatic)
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
            CommandGroup(replacing: .help) {
                Button("Activity Log…") {
                    viewModel.showActivityLog = true
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationTitle("DiskWise")
                    .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 340)
            } detail: {
                detailContent
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("View", selection: $viewModel.selectedPane) {
                                ForEach(DetailPane.allCases) { pane in
                                    Label {
                                        HStack(spacing: 6) {
                                            Text(pane.title)
                                            if pane == .duplicates, viewModel.duplicateGroups.count > 0 {
                                                Text("\(viewModel.duplicateGroups.count)")
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.9), in: Capsule())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    } icon: {
                                        Image(systemName: pane.icon)
                                    }
                                    .tag(pane)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 520)
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
                    }
            }
            .blur(radius: viewModel.isStartingUp || viewModel.showFullDiskAccessPrompt || viewModel.showWhatsNewTour || viewModel.showIndexRebuildPrompt || viewModel.showSavedScanPrompt ? 8 : 0)
            .allowsHitTesting(!viewModel.isStartingUp && !viewModel.showFullDiskAccessPrompt && !viewModel.showWhatsNewTour && !viewModel.showIndexRebuildPrompt && !viewModel.showSavedScanPrompt)

            if viewModel.isStartingUp {
                StartupSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    isPostUpgrade: viewModel.isPostUpgradeStartup,
                    currentMessage: viewModel.startupMessage,
                    completedSteps: viewModel.startupCompletedSteps,
                    activeStep: viewModel.startupActiveStep
                )
            }

            if viewModel.showIndexRebuildPrompt {
                IndexRebuildOverlay(
                    version: AppSettings.currentAppVersion,
                    onRebuild: { viewModel.dismissIndexRebuildPrompt(rebuildNow: true) },
                    onSkip: { viewModel.dismissIndexRebuildPrompt(rebuildNow: false) }
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

            if viewModel.showWhatsNewTour {
                ReleaseNotesSplashOverlay(
                    version: AppSettings.currentAppVersion,
                    onOpenSettings: { openSettings() },
                    onContinue: { viewModel.finishWhatsNewTour() }
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
        .animation(.easeInOut(duration: 0.22), value: viewModel.showFullDiskAccessPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showIndexRebuildPrompt)
        .animation(.easeInOut(duration: 0.22), value: viewModel.showSavedScanPrompt)
        .onChange(of: viewModel.showFullDiskAccessPrompt) { _, isShowing in
            if !isShowing {
                viewModel.stopPermissionPollingIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkPermissionOnAppActivation()
        }
        .onChange(of: viewModel.isBlockingLaunchFlow) { _, isBlocking in
            if !isBlocking {
                viewModel.schedulePostLaunchWork()
            }
        }
        .sheet(isPresented: $viewModel.showActivityLog) {
            ActivityLogSheet(activityLog: viewModel.activityLog)
        }
        .sheet(isPresented: $viewModel.showAbout) {
            AboutView(onOpenSettings: { openSettings() })
                .environmentObject(appSettings)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedPane {
        case .overview:
            DashboardView()
        case .maintenance:
            MaintenanceView()
        case .duplicates:
            DuplicatesView()
        case .ai:
            AskDiskWiseView()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedVolumePath) {
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

            if !viewModel.internalVolumes.isEmpty {
                Section {
                    ForEach(viewModel.internalVolumes) { volume in
                        DeviceSidebarRow(
                            volume: volume,
                            isSelected: viewModel.selectedVolumePath == volume.mountPath,
                            isIndexed: viewModel.isIndexed(volume),
                            isScanDisabled: viewModel.isVolumeBusy(volume),
                            onScan: { viewModel.scan(volume: volume) },
                            onScanFolder: { viewModel.scanFolder(on: volume) },
                            onEject: volume.isEjectable ? { viewModel.ejectVolume(volume) } : nil
                        )
                        .tag(volume.mountPath)
                    }
                } header: {
                    Label("Internal SSD", systemImage: "internaldrive")
                }
            }

            if !viewModel.externalVolumes.isEmpty {
                Section {
                    ForEach(viewModel.externalVolumes) { volume in
                        DeviceSidebarRow(
                            volume: volume,
                            isSelected: viewModel.selectedVolumePath == volume.mountPath,
                            isIndexed: viewModel.isIndexed(volume),
                            isScanDisabled: viewModel.isVolumeBusy(volume),
                            isEjectDisabled: viewModel.isVolumeBusy(volume),
                            onScan: { viewModel.scan(volume: volume) },
                            onScanFolder: { viewModel.scanFolder(on: volume) },
                            onEject: volume.isEjectable ? { viewModel.ejectVolume(volume) } : nil
                        )
                        .tag(volume.mountPath)
                    }
                } header: {
                    Label("External Drives", systemImage: "externaldrive")
                }
            }

            if viewModel.mountedVolumes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No devices found",
                        systemImage: "externaldrive.trianglebadge.exclamationmark",
                        description: Text("Connect a drive or grant Full Disk Access.")
                    )

                    Button("Grant Permission") {
                        viewModel.presentFullDiskAccessOverlay()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section {
                Button {
                    viewModel.refreshDrivesAfterPermissionChange()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                if let volume = viewModel.selectedVolume {
                    Button {
                        viewModel.scanSelectedVolume()
                    } label: {
                        Label(
                            viewModel.isScanning
                                ? "Identifying…"
                                : (viewModel.isAnalyzing
                                    ? "Analyzing…"
                                    : viewModel.scanActionTitle(for: volume)),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(viewModel.isVolumeBusy(volume))

                    Button {
                        viewModel.scanFolderOnSelectedVolume()
                    } label: {
                        Label(
                            viewModel.isScanning ? "Scanning…" : "Scan Folder…",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .disabled(viewModel.isVolumeBusy(volume))

                    Button {
                        viewModel.showActivityLog = true
                    } label: {
                        Label("Activity Log", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.borderless)

                    if viewModel.hasScanData {
                        Button {
                            viewModel.selectedPane = .maintenance
                        } label: {
                            Label("Maintenance", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            viewModel.openDuplicatesPane()
                            if !viewModel.isFindingDuplicates && viewModel.duplicateGroups.isEmpty {
                                viewModel.scanForDuplicates()
                            }
                        } label: {
                            Label {
                                if viewModel.isFindingDuplicates {
                                    Text("Finding duplicates…")
                                } else if viewModel.totalDuplicateSavings > 0 {
                                    Text("Duplicates · \(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.totalDuplicateSavings))")
                                } else {
                                    Text("Find Duplicates")
                                }
                            } icon: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .buttonStyle(.borderless)
                    }

                    if viewModel.canEjectSelectedVolume {
                        Button {
                            viewModel.ejectSelectedVolume()
                        } label: {
                            Label("Eject \(volume.name)", systemImage: "eject.fill")
                        }
                        .disabled(viewModel.isVolumeBusy(volume))
                    }
                }

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Actions")
            }
        }
        .onChange(of: viewModel.selectedVolumePath) { _, newValue in
            guard let newValue,
                  let volume = viewModel.mountedVolumes.first(where: { $0.mountPath == newValue }) else {
                return
            }
            viewModel.selectVolume(volume)
        }
    }
}
