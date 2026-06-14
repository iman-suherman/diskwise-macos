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
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 {
            let terabytes = gigabytes / 1000
            if terabytes >= 10 {
                return String(format: "%.0fTB", terabytes)
            }
            return String(format: "%.1fTB", terabytes)
        }
        if gigabytes >= 10 {
            return String(format: "%.0fGB", gigabytes)
        }
        return String(format: "%.1fGB", gigabytes)
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
    static let scanningHeight: CGFloat = 320
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

            Text("Keeps selected drives from sleeping or spinning down. Your Mac can still sleep.")
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
    @ObservedObject var monitor: SystemVolumeMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var scanActivity = ScanActivityMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scanActivity.isScanning ? "Scanning" : volumeName)
                        .font(.headline)
                    Text(scanActivity.isScanning ? scanSubtitle : "DiskWise menu bar monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !scanActivity.isScanning {
                    Button {
                        monitor.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh disk space now")
                }
            }

            if scanActivity.isScanning {
                scanProgressSection
            } else if let volume = monitor.systemVolume {
                diskUsageSection(volume)
            } else {
                ContentUnavailableView(
                    "Volume unavailable",
                    systemImage: "internaldrive.trianglebadge.exclamationmark",
                    description: Text("Could not read Macintosh HD capacity.")
                )
                .frame(maxWidth: .infinity)
            }

            if !scanActivity.isScanning {
                Button {
                    startMacintoshHDScan()
                } label: {
                    Label("Scan Macintosh HD", systemImage: "internaldrive.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canStartMacintoshHDScan)
            }

            Divider()

            Text("Menu bar display")
                .font(.subheadline.weight(.semibold))

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

            Divider()

            Button("Open DiskWise") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: MenuBarPopoverMetrics.width)
    }

    private var volumeName: String {
        monitor.systemVolume?.name ?? "Macintosh HD"
    }

    private var canStartMacintoshHDScan: Bool {
        guard let viewModel = AppViewModel.current else { return false }
        return !viewModel.isStartingUp && !viewModel.mountedVolumes.isEmpty
    }

    private func startMacintoshHDScan() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        AppViewModel.current?.scanInternalDrive()
    }

    private var scanSubtitle: String {
        if let volumeName = scanActivity.volumeName {
            return "Identifying \(volumeName)"
        }
        return "Identifying disk usage"
    }

    private var scanProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(scanActivity.progressPercentLabel)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let operationLabel = scanActivity.operationLabel {
                    Text(operationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: scanActivity.progressFraction)
                .progressViewStyle(.linear)

            if let detail = scanActivity.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
    private var popover: NSPopover?

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
            popover?.close()
            popover = nil
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
            self?.togglePopover(anchoredTo: container)
        }
        hostingView.frame.origin = .zero
        container.addSubview(hostingView)

        item.view = container
        return MenuBarStatusSlot(statusItem: item, containerView: container)
    }

    private func togglePopover(anchoredTo anchorView: NSView) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(
            width: MenuBarPopoverMetrics.width,
            height: ScanActivityMonitor.shared.isScanning ? MenuBarPopoverMetrics.scanningHeight : MenuBarPopoverMetrics.height
        )
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverContent(
                monitor: monitor,
                settings: AppSettings.shared
            )
        )
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.popover = popover
        monitor.refresh()
    }
}
