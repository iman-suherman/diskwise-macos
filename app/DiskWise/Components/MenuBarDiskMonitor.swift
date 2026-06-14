import AppKit
import DiskScannerKit
import SwiftUI

@MainActor
final class SystemVolumeMonitor: ObservableObject {
    static let shared = SystemVolumeMonitor()

    @Published private(set) var volumes: [MountedVolume] = []

    var systemVolume: MountedVolume? {
        volumes.first(where: { VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) })
            ?? volumes.first(where: \.isInternal)
    }

    func volume(for mountPath: String) -> MountedVolume? {
        volumes.first { $0.mountPath == mountPath }
    }

    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        startObserving()
    }

    deinit {
        refreshTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        volumes = VolumeDiscovery.mountedVolumes()
        pruneUnavailableMenuBarVolumes()
        let notificationsEnabled = AppSettings.shared.diskSpaceNotificationsEnabled
        Task {
            await DiskSpaceNotificationService.shared.checkVolumes(
                volumes,
                notificationsEnabled: notificationsEnabled
            )
        }
    }

    /// Refreshes free-space stats and re-enumerates all mounted drives for menu bar toggles.
    func refreshAllVolumes() {
        refresh()
        AppViewModel.current?.refreshMountedVolumes()
    }

    private func pruneUnavailableMenuBarVolumes() {
        let settings = AppSettings.shared
        let availablePaths = Set(volumes.map(\.mountPath))
        let staleMenuBarPaths = settings.menuBarFreeSpaceVolumePaths.subtracting(availablePaths)
        if !staleMenuBarPaths.isEmpty {
            settings.menuBarFreeSpaceVolumePaths.subtract(staleMenuBarPaths)
        }

        let staleKeepAwakePaths = settings.keepAwakeVolumePaths.subtracting(availablePaths)
        if !staleKeepAwakePaths.isEmpty {
            settings.keepAwakeVolumePaths.subtract(staleKeepAwakePaths)
        }
    }

    private func refreshInterval(for volume: MountedVolume?) -> Duration {
        guard let volume else { return .seconds(60) }
        let freeFraction = max(0, 1 - volume.usageFraction)
        if MenuBarDiskThresholds.isCriticallyLow(freeSize: volume.freeSize) {
            return .seconds(15)
        }
        if freeFraction < 0.15 {
            return .seconds(30)
        }
        return .seconds(60)
    }

    private func startObserving() {
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                let interval = refreshInterval(for: systemVolume)
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                refresh()
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            },
            workspace.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            },
        ]
    }
}

enum MenuBarDiskThresholds {
    static var physicalMemoryBytes: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    static func isCriticallyLow(freeSize: Int64) -> Bool {
        freeSize < physicalMemoryBytes * 2
    }

    static func statusColor(freeSize: Int64, freeFraction: Double) -> Color {
        if isCriticallyLow(freeSize: freeSize) {
            return .red
        }

        let fraction = max(0, min(1, freeFraction))
        if fraction >= 0.5 {
            return .green
        }
        if fraction >= 0.15 {
            return .orange
        }
        return Color(red: 1, green: 0.35 + (fraction / 0.15) * 0.35, blue: 0.2)
    }
}

enum MenuBarFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func gigabytes(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        return String(format: "%.2f GB", gigabytes)
    }

    static func compactFreeSpace(_ bytes: Int64) -> String {
        readableFreeSpace(bytes, includeSpace: false)
    }

    static func readableFreeSpace(_ bytes: Int64, includeSpace: Bool = true) -> String {
        let unit = includeSpace ? " " : ""
        guard bytes > 0 else { return includeSpace ? "0 B" : "0B" }

        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 {
            let terabytes = gigabytes / 1000
            if terabytes >= 10 {
                return String(format: "%.0f\(unit)TB", terabytes)
            }
            return String(format: "%.1f\(unit)TB", terabytes)
        }
        if gigabytes >= 10 {
            return String(format: "%.0f\(unit)GB", gigabytes)
        }
        if gigabytes >= 1 {
            return String(format: "%.1f\(unit)GB", gigabytes)
        }

        let megabytes = Double(bytes) / 1_000_000
        if megabytes >= 100 {
            return String(format: "%.0f\(unit)MB", megabytes)
        }
        if megabytes >= 1 {
            return String(format: "%.1f\(unit)MB", megabytes)
        }

        let kilobytes = Double(bytes) / 1_000
        if kilobytes >= 1 {
            return String(format: "%.0f\(unit)KB", kilobytes)
        }

        return includeSpace ? "\(bytes) B" : "\(bytes)B"
    }

    static func resolvedFreeBytes(for volume: MountedVolume) -> Int64 {
        let reported = max(0, volume.freeSize)
        guard volume.totalSize > 0 else { return reported }

        let implied = Int64((Double(volume.totalSize) * max(0, 1 - volume.usageFraction)).rounded())
        if reported == 0, implied > 0 {
            return implied
        }
        if reported > 0, implied > 0 {
            let ratio = Double(reported) / Double(implied)
            if ratio < 0.5 || ratio > 2.0 {
                return implied
            }
        }
        return reported > 0 ? reported : implied
    }

    static func menuBarShortVolumeName(_ volumeName: String) -> String {
        volumeName.split(separator: " ").last.map(String.init) ?? volumeName
    }

    static func menuBarFreeSpaceLabel(for volume: MountedVolume) -> String {
        let shortName = menuBarShortVolumeName(volume.name)
        return "\(shortName) (\(compactFreeSpace(volume.freeSize)))"
    }
}

struct MenuBarVolumeFreeSpaceLabel: View {
    let volume: MountedVolume

    var body: some View {
        Text(MenuBarFormatters.menuBarFreeSpaceLabel(for: volume))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(statusColor)
            .padding(.horizontal, 2)
            .accessibilityLabel(accessibilityLabel)
    }

    private var freeFraction: Double {
        max(0, min(1, 1 - volume.usageFraction))
    }

    private var statusColor: Color {
        MenuBarDiskThresholds.statusColor(
            freeSize: volume.freeSize,
            freeFraction: freeFraction
        )
    }

    private var accessibilityLabel: String {
        "\(volume.name), \(MenuBarFormatters.compactFreeSpace(volume.freeSize)) remaining"
    }
}

/// Sidebar badge matching menu bar `HD (256GB)` free-space label and color thresholds.
struct SidebarDiskFreeSpaceBadge: View {
    let volume: MountedVolume

    var body: some View {
        Text(MenuBarFormatters.menuBarFreeSpaceLabel(for: volume))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(statusColor)
            .accessibilityLabel(accessibilityLabel)
    }

    private var freeFraction: Double {
        max(0, min(1, 1 - volume.usageFraction))
    }

    private var statusColor: Color {
        MenuBarDiskThresholds.statusColor(
            freeSize: volume.freeSize,
            freeFraction: freeFraction
        )
    }

    private var accessibilityLabel: String {
        "\(volume.name), \(MenuBarFormatters.compactFreeSpace(volume.freeSize)) remaining"
    }
}

struct MenuBarVolumeFreeSpaceLabelView: View {
    @ObservedObject var monitor: SystemVolumeMonitor
    let mountPath: String

    var body: some View {
        if let volume = monitor.volume(for: mountPath) {
            MenuBarVolumeFreeSpaceLabel(volume: volume)
        } else {
            Text("—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

enum MenuBarPopoverMetrics {
    static let width: CGFloat = 520
    static let height: CGFloat = 500
    static let scanningHeight: CGFloat = 360
    static let unindexedHeight: CGFloat = 440

    @MainActor
    static func popoverHeight(
        mountPath: String,
        isIndexed: Bool,
        scanActivity: ScanActivityMonitor
    ) -> CGFloat {
        if scanActivity.isScanningVolume(mountPath) {
            return scanningHeight
        }
        if !isIndexed {
            return unindexedHeight
        }
        return height
    }
}

struct MenuBarPopoverCloseButton: View {
    var onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Close")
    }
}

struct MenuBarKeepAwakeSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var keepAwake = KeepAwakeController.shared
    let volumes: [MountedVolume]
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text("Keep Disks Awake")
                .font(.subheadline.weight(.semibold))

            Text("Keeps selected drives from sleeping by writing a tiny temporary file on each drive every 20 seconds (Amphetamine-style). Your Mac can still sleep.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if volumes.isEmpty {
                Text("No drives detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(volumes) { volume in
                    keepAwakeToggle(for: volume)
                }
            }

            if let systemVolume = volumes.first(where: { VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) }) {
                Text("\(systemVolume.name) is always kept awake — DiskWise and macOS require the system drive to stay mounted.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if keepAwake.isActive {
                let awakeCount = keepAwake.activeVolumePaths.count
                Label(
                    "Keeping \(awakeCount) drive\(awakeCount == 1 ? "" : "s") from sleeping",
                    systemImage: "internaldrive"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func keepAwakeToggle(for volume: MountedVolume) -> some View {
        let isSystem = VolumeDiscovery.isSystemVolume(mountPath: volume.mountPath)
        Toggle(
            keepAwakeVolumeLabel(volume),
            isOn: Binding(
                get: { settings.isKeepAwakeVolumeEnabled(for: volume.mountPath) },
                set: { settings.setKeepAwakeVolumeEnabled(for: volume.mountPath, enabled: $0) }
            )
        )
        .disabled(isSystem)
    }

    private func keepAwakeVolumeLabel(_ volume: MountedVolume) -> String {
        let kind = volume.isInternal ? "Internal" : "External"
        return "\(volume.name) (\(kind))"
    }
}

struct MenuBarVolumeToggleSection: View {
    @ObservedObject var settings: AppSettings
    let volumes: [MountedVolume]
    var showsSectionTitle: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSectionTitle {
                Text("Show free space in menu bar")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Menu bar drives")
                    .font(.subheadline.weight(.semibold))
            }

            if volumes.isEmpty {
                Text("No drives detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(volumes) { volume in
                    Toggle(
                        volumeToggleLabel(volume),
                        isOn: Binding(
                            get: { settings.isMenuBarFreeSpaceVisible(for: volume.mountPath) },
                            set: { settings.setMenuBarFreeSpaceVisible(for: volume.mountPath, visible: $0) }
                        )
                    )
                }
            }
        }
    }

    private func volumeToggleLabel(_ volume: MountedVolume) -> String {
        let kind = volume.isInternal ? "Internal" : "External"
        return "\(volume.name) (\(kind))"
    }
}

struct MenuBarPopoverContent: View {
    let mountPath: String
    @ObservedObject var monitor: SystemVolumeMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var scanActivity = ScanActivityMonitor.shared
    var onOpenMainWindow: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var isRefreshingVolumes = false

    private var volume: MountedVolume? {
        monitor.volume(for: mountPath)
    }

    private var isScanningThisVolume: Bool {
        scanActivity.isScanningVolume(mountPath)
    }

    private var isIndexed: Bool {
        guard let volume else { return false }
        return viewModel.isIndexed(volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isScanningThisVolume {
                scanProgressSection
            } else if let volume {
                diskUsageSection(volume)

                if isIndexed {
                    indexedScanActions(for: volume)
                } else {
                    unindexedScanPrompt(for: volume)
                }
            } else {
                ContentUnavailableView(
                    "Volume unavailable",
                    systemImage: "internaldrive.trianglebadge.exclamationmark",
                    description: Text("This drive is no longer mounted.")
                )
                .frame(maxWidth: .infinity)
            }

            Divider()

            menuBarSettingsSection

            Divider()

            Button("Open DiskWise") {
                MenuBarMainWindowOpener.open(dismissingPopover: onOpenMainWindow)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: MenuBarPopoverMetrics.width)
        .onAppear {
            viewModel.reload()
            monitor.refreshAllVolumes()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isScanningThisVolume ? "Scanning" : (volume?.name ?? "Drive"))
                    .font(.headline)
                Text(isScanningThisVolume ? scanSubtitle : headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isScanningThisVolume {
                Button {
                    refreshVolumes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh disk space and drive list")
                .disabled(isRefreshingVolumes)
            }

            if let onClose {
                MenuBarPopoverCloseButton(onClose: onClose)
            }
        }
    }

    private var headerSubtitle: String {
        guard let volume else { return "DiskWise menu bar monitor" }
        let kind = volume.isInternal ? "Internal drive" : "External drive"
        if isIndexed {
            return "\(kind) · indexed"
        }
        return "\(kind) · not indexed yet"
    }

    @ViewBuilder
    private func unindexedScanPrompt(for volume: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This drive has not been scanned yet. DiskWise only knows capacity from macOS until you run a scan.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose Fast scan for a quick first pass, or Deep scan to map every file individually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    startScan(for: volume, mode: .fast)
                } label: {
                    Label("Fast Scan", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartScan(for: volume))

                Button {
                    startScan(for: volume, mode: .deep)
                } label: {
                    Label("Deep Scan", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!canStartScan(for: volume))
            }

            if viewModel.isScanning && !isScanningThisVolume {
                Text("Another drive is scanning. Wait for it to finish before starting a new scan.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func indexedScanActions(for volume: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rescan this drive")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    startScan(for: volume, mode: .fast)
                } label: {
                    Label("Fast Scan", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canStartScan(for: volume))

                Button {
                    startScan(for: volume, mode: .deep)
                } label: {
                    Label("Deep Scan", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!canStartScan(for: volume))
            }
        }
    }

    @ViewBuilder
    private var menuBarSettingsSection: some View {
        HStack {
            Text("Menu bar display")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                refreshVolumes()
            } label: {
                Label("Refresh drives", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Re-scan for newly connected or ejected drives")
            .disabled(isRefreshingVolumes)
        }

        HStack(alignment: .top, spacing: 24) {
            MenuBarKeepAwakeSection(
                settings: settings,
                volumes: monitor.volumes,
                compact: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            MenuBarVolumeToggleSection(
                settings: settings,
                volumes: monitor.volumes,
                showsSectionTitle: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 24) {
            Toggle(
                "Show health score",
                isOn: Binding(
                    get: { settings.showMenuBarHealthScore },
                    set: { settings.setMenuBarHealthScoreVisible($0) }
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "Show DiskWise in Dock",
                isOn: Binding(
                    get: { !settings.hideFromDock },
                    set: { settings.setHideFromDock(!$0) }
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func canStartScan(for volume: MountedVolume) -> Bool {
        !viewModel.isStartingUp && !viewModel.isScanning
    }

    private func startScan(for volume: MountedVolume, mode: ScanMode) {
        viewModel.startMenuBarScan(for: volume, mode: mode)
    }

    private func refreshVolumes() {
        guard !isRefreshingVolumes else { return }
        isRefreshingVolumes = true
        monitor.refreshAllVolumes()
        viewModel.reload()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            isRefreshingVolumes = false
        }
    }

    private var scanSubtitle: String {
        let modeLabel = scanActivity.scanMode.title
        if let volumeName = scanActivity.volumeName {
            return "\(modeLabel) scan · \(volumeName)"
        }
        return "\(modeLabel) scan"
    }

    private var scanProgressSection: some View {
        let isDeepScan = scanActivity.scanMode == .deep
        let accent = isDeepScan ? Color.orange : Color.accentColor

        return VStack(alignment: .leading, spacing: 12) {
            Label(
                "\(scanActivity.scanMode.title) Scan",
                systemImage: isDeepScan ? "scope" : "bolt.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)

            HStack(alignment: .firstTextBaseline) {
                Text(scanActivity.progressPercentLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Spacer()
                if let operationLabel = scanActivity.operationLabel {
                    Text(operationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: scanActivity.progressFraction)
                .progressViewStyle(.linear)
                .tint(accent)

            if let detail = scanActivity.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(accent.opacity(isDeepScan ? 0.08 : 0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(isDeepScan ? 0.2 : 0.14), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func diskUsageSection(_ volume: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Used \(Int((volume.usageFraction * 100).rounded()))%")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(usageColor(for: volume))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    statHeader("Total")
                    Spacer()
                    statHeader("Used")
                    Spacer()
                    statHeader("Free")
                }

                HStack {
                    statValue(MenuBarFormatters.gigabytes(volume.totalSize))
                    Spacer()
                    statValue(MenuBarFormatters.gigabytes(volume.usedSize))
                    Spacer()
                    statValue(MenuBarFormatters.gigabytes(volume.freeSize))
                }
            }
        }
    }

    private func usageColor(for volume: MountedVolume) -> Color {
        MenuBarDiskThresholds.statusColor(
            freeSize: volume.freeSize,
            freeFraction: max(0, 1 - volume.usageFraction)
        )
    }

    private func statHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statValue(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class MenuBarClickableStatusView: NSView {
    var onClick: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private let monitor = SystemVolumeMonitor.shared
    private var volumeSlots: [String: MenuBarStatusSlot] = [:]
    private let popoverSession = MenuBarPopoverSession()

    private struct MenuBarStatusSlot {
        let statusItem: NSStatusItem
        let containerView: MenuBarClickableStatusView
    }

    private override init() {
        super.init()
    }

    func syncFreeSpaceVolumes(enabledPaths: Set<String>) {
        let sortedPaths = enabledPaths.sorted()
        for (mountPath, slot) in volumeSlots where !enabledPaths.contains(mountPath) {
            NSStatusBar.system.removeStatusItem(slot.statusItem)
            volumeSlots.removeValue(forKey: mountPath)
        }

        for mountPath in sortedPaths {
            guard monitor.volume(for: mountPath) != nil else { continue }
            if volumeSlots[mountPath] == nil {
                volumeSlots[mountPath] = makeVolumeSlot(mountPath: mountPath)
            }
        }

        if enabledPaths.isEmpty {
            popoverSession.close()
        }
    }

    private func makeVolumeSlot(mountPath: String) -> MenuBarStatusSlot {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let label = MenuBarFormatters.menuBarFreeSpaceLabel(
            for: monitor.volume(for: mountPath)!
        )
        let estimatedWidth = max(58, CGFloat(label.count * 7 + 8))
        let hostingView = NSHostingView(
            rootView: MenuBarVolumeFreeSpaceLabelView(monitor: monitor, mountPath: mountPath)
        )
        hostingView.frame.size = NSSize(width: estimatedWidth, height: 18)

        let container = MenuBarClickableStatusView(frame: hostingView.frame)
        container.onClick = { [weak self, weak container] in
            guard let container else { return }
            self?.togglePopover(anchoredTo: container, mountPath: mountPath)
        }
        hostingView.frame.origin = .zero
        container.addSubview(hostingView)

        item.view = container
        return MenuBarStatusSlot(statusItem: item, containerView: container)
    }

    private func togglePopover(anchoredTo anchorView: NSView, mountPath: String) {
        let viewModel = AppViewModel.current
        let volume = monitor.volume(for: mountPath)
        let isIndexed = volume.map { viewModel?.isIndexed($0) ?? false } ?? false
        let height = MenuBarPopoverMetrics.popoverHeight(
            mountPath: mountPath,
            isIndexed: isIndexed,
            scanActivity: ScanActivityMonitor.shared
        )

        popoverSession.toggle(
            anchoredTo: anchorView,
            contentSize: NSSize(width: MenuBarPopoverMetrics.width, height: height)
        ) {
            if let viewModel {
                MenuBarPopoverContent(
                    mountPath: mountPath,
                    monitor: monitor,
                    settings: AppSettings.shared,
                    viewModel: viewModel,
                    onOpenMainWindow: { [weak self] in self?.popoverSession.close() },
                    onClose: { [weak self] in self?.popoverSession.close() }
                )
            } else {
                Text("DiskWise is starting…")
                    .padding(24)
                    .frame(width: MenuBarPopoverMetrics.width)
            }
        } onShow: { [monitor] in
            monitor.refreshAllVolumes()
            AppViewModel.current?.reload()
        }
    }
}
