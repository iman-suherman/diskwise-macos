import AppKit
import DiskScannerKit
import SwiftUI

@MainActor
final class SystemVolumeMonitor: ObservableObject {
    @Published private(set) var systemVolume: MountedVolume?

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
        let volumes = VolumeDiscovery.mountedVolumes()
        systemVolume = volumes.first(where: { VolumeDiscovery.isSystemVolume(mountPath: $0.mountPath) })
            ?? volumes.first(where: \.isInternal)
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

struct MenuBarStatusLabel: View {
    let volume: MountedVolume?

    var body: some View {
        Text(remainingPercentLabel)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(statusColor)
            .padding(.horizontal, 2)
            .accessibilityLabel(accessibilityLabel)
    }

    private var freeFraction: Double {
        guard let volume else { return 0 }
        return max(0, min(1, 1 - volume.usageFraction))
    }

    private var remainingPercentLabel: String {
        guard volume != nil else { return "—" }
        return String(format: "%.0f%%", freeFraction * 100)
    }

    private var statusColor: Color {
        guard let volume else { return .secondary }
        return MenuBarDiskThresholds.statusColor(
            freeSize: volume.freeSize,
            freeFraction: freeFraction
        )
    }

    private var accessibilityLabel: String {
        guard let volume else { return "Disk space unavailable" }
        let freePercent = Int((freeFraction * 100).rounded())
        let usedPercent = Int((volume.usageFraction * 100).rounded())
        return "\(volume.name), \(freePercent) percent free, \(usedPercent) percent used"
    }
}

struct MenuBarPopoverContent: View {
    @ObservedObject var monitor: SystemVolumeMonitor
    var onHideMonitor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(volumeName)
                        .font(.headline)
                    Text("DiskWise menu bar monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh disk space now")
            }

            if let volume = monitor.systemVolume {
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
            } else {
                ContentUnavailableView(
                    "Volume unavailable",
                    systemImage: "internaldrive.trianglebadge.exclamationmark",
                    description: Text("Could not read Macintosh HD capacity.")
                )
                .frame(maxWidth: .infinity)
            }

            Divider()

            Button("Open DiskWise") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            Button("Hide Menu Bar Monitor") {
                onHideMonitor()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var volumeName: String {
        monitor.systemVolume?.name ?? "Macintosh HD"
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
}

struct MenuBarStatusLabelView: View {
    @ObservedObject var monitor: SystemVolumeMonitor

    var body: some View {
        MenuBarStatusLabel(volume: monitor.systemVolume)
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

    private let monitor = SystemVolumeMonitor()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusView: MenuBarClickableStatusView?

    private override init() {
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            installIfNeeded()
        } else {
            uninstall()
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let hostingView = NSHostingView(rootView: MenuBarStatusLabelView(monitor: monitor))
        hostingView.frame.size = NSSize(width: 44, height: 18)

        let container = MenuBarClickableStatusView(frame: hostingView.frame)
        container.onClick = { [weak self] in
            self?.togglePopover()
        }
        hostingView.frame.origin = .zero
        container.addSubview(hostingView)

        item.view = container
        statusItem = item
        statusView = container
    }

    private func uninstall() {
        popover?.close()
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusView = nil
    }

    private func togglePopover() {
        guard let anchorView = statusView ?? statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverContent(
                monitor: monitor,
                onHideMonitor: { [weak self] in
                    AppSettings.shared.setMenuBarDiskMonitorEnabled(false)
                    self?.popover?.performClose(nil)
                }
            )
        )
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.popover = popover
        monitor.refresh()
    }
}
