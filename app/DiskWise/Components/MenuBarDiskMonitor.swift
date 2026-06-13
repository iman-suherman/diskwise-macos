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

    private func startObserving() {
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
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
        if freeFraction < 0.15 {
            return .orange
        }
        return .green
    }
}

struct MenuBarStatusLabel: View {
    let volume: MountedVolume?

    var body: some View {
        HStack(spacing: 6) {
            Text(remainingPercentLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(statusColor)

            MenuBarRemainingBar(
                freeFraction: freeFraction,
                statusColor: statusColor
            )
            .frame(width: 36, height: 5)
        }
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

struct MenuBarRemainingBar: View {
    let freeFraction: Double
    let statusColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))

                Capsule()
                    .fill(statusColor)
                    .frame(width: max(0, geometry.size.width * min(max(freeFraction, 0), 1)))
            }
        }
    }
}

struct MenuBarPopoverContent: View {
    @ObservedObject var monitor: SystemVolumeMonitor
    var onHideMonitor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(volumeName)
                    .font(.headline)
                Text("DiskWise menu bar monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        hostingView.frame.size = NSSize(width: 72, height: 18)

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
    }
}
