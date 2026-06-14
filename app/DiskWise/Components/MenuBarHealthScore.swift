import AppKit
import DiskScannerKit
import SwiftUI

struct MenuBarHealthScoreLabel: View {
    let score: Int

    var body: some View {
        Text(SystemHealthMonitorCore.healthConditionLabelWithScore(for: score))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(scoreColor)
            .padding(.horizontal, 2)
            .accessibilityLabel("System health \(SystemHealthMonitorCore.healthConditionLabel(for: score)), score \(score)")
    }

    private var scoreColor: Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct MenuBarHealthScoreLabelView: View {
    @ObservedObject var monitor: SystemHealthMonitor

    var body: some View {
        MenuBarHealthScoreLabel(score: monitor.snapshot?.healthScore ?? 0)
    }
}

struct MenuBarHealthPopoverContent: View {
    @ObservedObject var monitor: SystemHealthMonitor
    @ObservedObject var settings: AppSettings
    var onOpenMainWindow: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let snapshot = monitor.snapshot {
                    scoreSection(snapshot)
                    metricsGrid(snapshot)
                    SystemMemoryReliefControl(
                        monitor: monitor,
                        snapshot: snapshot,
                        compact: true
                    )
                    detailsSection(snapshot)
                    topProcessesSection(snapshot)
                } else {
                    ContentUnavailableView(
                        "System status unavailable",
                        systemImage: "heart.text.square",
                        description: Text("Could not read system metrics.")
                    )
                }

                Divider()

                menuBarDisplaySection

                Divider()

                Button("Open DiskWise") {
                    MenuBarMainWindowOpener.open(dismissingPopover: onOpenMainWindow)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .frame(width: MenuBarPopoverMetrics.width, height: MenuBarPopoverMetrics.height)
    }

    private var header: some View {
        HStack {
            Text("System Status")
                .font(.headline)
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh system metrics")
        }
    }

    @ViewBuilder
    private func scoreSection(_ snapshot: SystemHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Health Score")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SystemHealthMonitorCore.healthConditionLabelWithScore(for: snapshot.healthScore))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(snapshot.healthScore))

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hostName)
                        .font(.subheadline.weight(.semibold))
                    Text("Version \(snapshot.macOSVersion) (Build \(snapshot.macOSBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func metricsGrid(_ snapshot: SystemHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                metricHeader("CPU")
                Spacer()
                metricHeader("Memory")
            }
            HStack {
                metricValue(String(format: "%.1f%%", snapshot.cpuUsagePercent))
                Spacer()
                metricValue(String(format: "%.1f%%", snapshot.memoryUsedPercent))
            }

            Text("Load \(formatLoad(snapshot.loadAverage1)) / \(snapshot.processorCount) cores \(formatGB(snapshot.memoryUsedBytes)) used")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack {
                metricHeader("Disk")
                Spacer()
                metricHeader("Uptime")
            }
            HStack {
                metricValue(String(format: "%.1f%%", snapshot.diskUsedPercent))
                Spacer()
                metricValue(formatUptime(snapshot.uptimeSeconds))
            }

            Text("\(formatGB(snapshot.diskFreeBytes)) free \(snapshot.machineModel)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailsSection(_ snapshot: SystemHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Details")
                .font(.subheadline.weight(.semibold))

            detailRow("Total memory", formatGB(snapshot.physicalMemoryBytes))
            detailRow("Disk capacity", formatGB(snapshot.diskTotalBytes))
            detailRow(
                "Load average",
                String(
                    format: "%.2f • %.2f • %.2f",
                    snapshot.loadAverage1,
                    snapshot.loadAverage5,
                    snapshot.loadAverage15
                )
            )
        }
    }

    @ViewBuilder
    private func topProcessesSection(_ snapshot: SystemHealthSnapshot) -> some View {
        HStack(alignment: .top, spacing: 24) {
            processList(title: "Top CPU", processes: snapshot.topCPUProcesses, showCPU: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            processList(title: "Top Memory", processes: snapshot.topMemoryProcesses, showCPU: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func processList(title: String, processes: [ProcessUsage], showCPU: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if processes.isEmpty {
                Text("No process data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack {
                        Text(SystemHealthMonitorCore.truncatedProcessName(process.name))
                            .font(.caption)
                            .lineLimit(1)
                            .help(process.name)
                        Spacer()
                        Text(
                            showCPU
                                ? String(format: "%.1f%%", process.cpuPercent)
                                : formatGB(process.memoryBytes)
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu bar display")
                .font(.subheadline.weight(.semibold))

            Toggle(
                "Show health score",
                isOn: Binding(
                    get: { settings.showMenuBarHealthScore },
                    set: { settings.setMenuBarHealthScoreVisible($0) }
                )
            )

            MenuBarVolumeToggleSection(
                settings: settings,
                volumes: SystemVolumeMonitor.shared.volumes
            )

            Toggle(
                "Show DiskWise in Dock",
                isOn: Binding(
                    get: { !settings.hideFromDock },
                    set: { settings.setHideFromDock(!$0) }
                )
            )
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func metricHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricValue(_ value: String) -> some View {
        Text(value)
            .font(.body.monospacedDigit().weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func formatGB(_ bytes: Int64) -> String {
        MenuBarFormatters.gigabytes(bytes)
    }

    private func formatLoad(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

@MainActor
final class MenuBarHealthItemController: NSObject {
    static let shared = MenuBarHealthItemController()

    private let monitor = SystemHealthMonitor.shared
    private var healthSlot: MenuBarStatusSlot?
    private let popoverSession = MenuBarPopoverSession()

    private struct MenuBarStatusSlot {
        let statusItem: NSStatusItem
        let containerView: MenuBarClickableStatusView
    }

    private override init() {
        super.init()
    }

    func syncVisibility(showHealthScore: Bool) {
        if showHealthScore {
            if healthSlot == nil {
                healthSlot = makeSlot()
            }
        } else if let existing = healthSlot {
            popoverSession.close()
            NSStatusBar.system.removeStatusItem(existing.statusItem)
            healthSlot = nil
        }
    }

    func prepareDuringLaunch(systemVolume: MountedVolume?) async {
        await monitor.warmUpQuick(volume: systemVolume)
        syncVisibility(showHealthScore: AppSettings.shared.showMenuBarHealthScore)
        monitor.enrichProcessesInBackground()
    }

    private func makeSlot() -> MenuBarStatusSlot {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let hostingView = NSHostingView(rootView: MenuBarHealthScoreLabelView(monitor: monitor))
        hostingView.frame.size = NSSize(width: 64, height: 18)

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
        popoverSession.toggle(
            anchoredTo: anchorView,
            contentSize: NSSize(
                width: MenuBarPopoverMetrics.width,
                height: MenuBarPopoverMetrics.height
            )
        ) {
            MenuBarHealthPopoverContent(
                monitor: monitor,
                settings: AppSettings.shared,
                onOpenMainWindow: { [weak self] in self?.popoverSession.close() }
            )
        } onShow: { [monitor] in
            monitor.refresh()
        }
    }
}
