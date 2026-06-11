import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .defaultSize(width: 1320, height: 880)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

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
                                    Label(pane.title, systemImage: pane.icon).tag(pane)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)
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
            .blur(radius: viewModel.showFullDiskAccessPrompt ? 8 : 0)
            .allowsHitTesting(!viewModel.showFullDiskAccessPrompt)

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
        .animation(.easeInOut(duration: 0.22), value: viewModel.showFullDiskAccessPrompt)
        .onAppear {
            viewModel.presentFullDiskAccessPromptIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkPermissionOnAppActivation()
        }
        .onChange(of: viewModel.showFullDiskAccessPrompt) { _, isShowing in
            if !isShowing {
                viewModel.stopPermissionPollingIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedPane {
        case .overview:
            DashboardView()
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
                            viewModel.isScanning ? "Scanning…" : (viewModel.isFindingDuplicates ? "Checking duplicates…" : "Rescan \(volume.name)"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(viewModel.isScanning)

                    if viewModel.canEjectSelectedVolume {
                        Button {
                            viewModel.ejectSelectedVolume()
                        } label: {
                            Label("Eject \(volume.name)", systemImage: "eject.fill")
                        }
                        .disabled((viewModel.isScanning || viewModel.isFindingDuplicates) && viewModel.selectedVolumePath == volume.mountPath)
                    }
                }
            } header: {
                Text("Actions")
            }
        }
        .onChange(of: viewModel.selectedVolumePath) { _, newValue in
            guard let newValue,
                  let volume = viewModel.mountedVolumes.first(where: { $0.mountPath == newValue }) else {
                return
            }
            viewModel.selectVolume(volume, autoScan: !viewModel.isIndexed(volume))
        }
    }
}
