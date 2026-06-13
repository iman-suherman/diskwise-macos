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

struct MenuBarStatusLabel: View {
    let volume: MountedVolume?

    var body: some View {
        HStack(spacing: 6) {
            Text(usagePercentLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()

            MenuBarUsageBar(fraction: usageFraction)
                .frame(width: 36, height: 5)
        }
        .padding(.horizontal, 2)
        .accessibilityLabel(accessibilityLabel)
    }

    private var usageFraction: Double {
        volume?.usageFraction ?? 0
    }

    private var usagePercentLabel: String {
        guard volume != nil else { return "—" }
        return String(format: "%.0f%%", usageFraction * 100)
    }

    private var accessibilityLabel: String {
        guard let volume else { return "Disk space unavailable" }
        let percent = Int((usageFraction * 100).rounded())
        return "\(volume.name) \(percent) percent used"
    }
}

struct MenuBarUsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))

                Capsule()
                    .fill(usageColor(for: fraction))
                    .frame(width: max(0, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
    }

    private func usageColor(for fraction: Double) -> Color {
        switch fraction {
        case 0.9...: return .red
        case 0.75..<0.9: return .orange
        default: return .accentColor
        }
    }
}

struct MenuBarPopoverContent: View {
    @ObservedObject var monitor: SystemVolumeMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

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
                .help("Refresh")
            }

            if let volume = monitor.systemVolume {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Used")
                        Spacer()
                        Text("\(Int((volume.usageFraction * 100).rounded()))%")
                            .font(.body.monospacedDigit().weight(.semibold))
                    }

                    ProgressView(value: volume.usageFraction)
                        .tint(usageColor(for: volume.usageFraction))

                    HStack {
                        statColumn(title: "Total", value: MenuBarFormatters.bytes.string(fromByteCount: volume.totalSize))
                        Spacer()
                        statColumn(title: "Used", value: MenuBarFormatters.bytes.string(fromByteCount: volume.usedSize))
                        Spacer()
                        statColumn(title: "Free", value: MenuBarFormatters.bytes.string(fromByteCount: volume.freeSize))
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

            Button("Show DiskWise") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var volumeName: String {
        monitor.systemVolume?.name ?? "Macintosh HD"
    }

    @ViewBuilder
    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func usageColor(for fraction: Double) -> Color {
        switch fraction {
        case 0.9...: return .red
        case 0.75..<0.9: return .orange
        default: return .accentColor
        }
    }
}

enum MenuBarFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

struct MenuBarStatusLabelView: View {
    @ObservedObject var monitor: SystemVolumeMonitor

    var body: some View {
        MenuBarStatusLabel(volume: monitor.systemVolume)
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private let monitor = SystemVolumeMonitor()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

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
        item.view = hostingView
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func uninstall() {
        popover?.close()
        popover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverContent(monitor: monitor)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }
}
