import SwiftUI
import AppKit
import MaintenanceKit

struct MaintenanceView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        HSplitView {
            maintenanceSidebar
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)

            maintenanceDetail
                .frame(minWidth: 520)
        }
        .navigationTitle("System Maintenance")
        .onAppear {
            if viewModel.systemSnapshot == nil {
                viewModel.refreshSystemSnapshot()
            }
        }
    }

    private var maintenanceSidebar: some View {
        List(selection: $viewModel.selectedMaintenanceKind) {
            ForEach(MaintenanceKind.groupedBySection, id: \.section) { group in
                Section(group.section.title) {
                    ForEach(group.kinds) { kind in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        } icon: {
                            Image(systemName: kind.icon)
                        }
                        .tag(kind)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: viewModel.selectedMaintenanceKind) { _, newKind in
            if newKind == .systemStatus {
                viewModel.refreshSystemSnapshot()
            }
        }
    }

    @ViewBuilder
    private var maintenanceDetail: some View {
        switch viewModel.selectedMaintenanceKind {
        case .apfsSnapshots:
            APFSSnapshotsPanel()
        case .appUninstall:
            AppUninstallPanel()
        case .optimize:
            OptimizePanel()
        case .systemStatus:
            SystemStatusPanel()
        default:
            MaintenanceScanPanel(kind: viewModel.selectedMaintenanceKind)
        }
    }
}

private struct APFSSnapshotsPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("APFS Snapshots", systemImage: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                Text("Local Time Machine snapshots pin deleted file blocks. Thinning them is often the fastest way to reclaim space after cleanup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isMaintenanceScanning {
                ProgressView("Listing snapshots…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.maintenanceScanResult {
                if result.entries.isEmpty {
                    ContentUnavailableView(
                        "No local snapshots",
                        systemImage: "checkmark.circle",
                        description: Text("macOS is not pinning deleted blocks via local snapshots right now.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("\(result.entries.count) snapshot(s) found")
                        .font(.headline)

                    List(result.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.label)
                                .font(.subheadline.weight(.medium))
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Thin All Snapshots") {
                            viewModel.executeAPFSSnapshotThinning()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Check for pinned space",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("List local snapshots on your system volume.")
                    )
                    Button("List Snapshots") {
                        viewModel.scanMaintenance(.apfsSnapshots)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
    }
}

private struct MaintenanceScanPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let kind: MaintenanceKind

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isMaintenanceScanning {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.maintenanceScanResult {
                if result.entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing found",
                        systemImage: kind.icon,
                        description: Text("No reclaimable items in this category right now.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    categorySummary(result)
                    selectionToolbar
                    entryList(result)
                    cleanupFooter
                }
            } else {
                emptyState
            }
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(kind.title, systemImage: kind.icon)
                .font(.title2.weight(.semibold))
            Text(kind.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Scan to find reclaimable space",
                systemImage: kind.icon,
                description: Text("DiskWise scans known locations safely — always preview before moving to Trash.")
            )
            Button("Scan Now") {
                viewModel.scanMaintenance(kind)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categorySummary(_ result: MaintenanceScanResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(result.categorySummaries) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.category.displayName)
                            .font(.caption.weight(.semibold))
                        Text(DiskWiseFormatters.bytes.string(fromByteCount: summary.totalSize))
                            .font(.subheadline.weight(.medium))
                        Text("\(summary.entryCount) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(viewModel.selectedMaintenanceEntries.count) selected · \(DiskWiseFormatters.bytes.string(fromByteCount: viewModel.selectedMaintenanceBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Select All") { viewModel.selectAllMaintenanceEntries(true) }
            Button("Clear") { viewModel.selectAllMaintenanceEntries(false) }
            Button("Rescan") { viewModel.scanMaintenance(kind) }
        }
        .buttonStyle(.borderless)
    }

    private func entryList(_ result: MaintenanceScanResult) -> some View {
        List(result.entries) { entry in
            MaintenanceEntryRow(
                entry: entry,
                isSelected: viewModel.maintenanceSelectedEntryIDs.contains(entry.id),
                onToggle: { viewModel.toggleMaintenanceEntry(entry) },
                onReveal: { NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "") }
            )
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 240)
    }

    private var cleanupFooter: some View {
        HStack {
            if kind == .nodeModules || kind == .buildArtifacts || kind == .virtualEnvironments {
                Label("Projects modified in the last 7 days are unselected by default.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Selected items move to Trash — recoverable from Finder.", systemImage: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Move Selected to Trash") {
                viewModel.executeMaintenanceCleanup()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedMaintenanceEntries.isEmpty)
        }
    }
}

private struct MaintenanceEntryRow: View {
    let entry: MaintenanceEntry
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.label)
                        .font(.body.weight(.medium))
                    if entry.isRecent {
                        Text("Recent")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(DiskWiseFormatters.bytes.string(fromByteCount: entry.size))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: onReveal) {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
    }
}

private struct AppUninstallPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var appPendingUninstall: InstalledApp?
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uninstall Apps", systemImage: "app.badge.minus.fill")
                .font(.title2.weight(.semibold))

            Text("Remove applications and their support files, caches, containers, and preferences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button(viewModel.isMaintenanceScanning ? "Scanning…" : "Scan Applications") {
                    viewModel.scanMaintenance(.appUninstall)
                }
                .disabled(viewModel.isMaintenanceScanning)

                if !viewModel.installedApps.isEmpty {
                    Text("\(viewModel.installedApps.count) apps found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.installedApps.isEmpty {
                ContentUnavailableView(
                    "Scan to list apps",
                    systemImage: "app.badge",
                    description: Text("DiskWise finds related files across Application Support, Caches, Containers, and Preferences.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.installedApps) { app in
                    AppUninstallRow(app: app) {
                        appPendingUninstall = app
                        showUninstallConfirm = true
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(24)
        .alert("Uninstall \(appPendingUninstall?.name ?? "app")?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let app = appPendingUninstall {
                    viewModel.uninstallSelectedApp(app)
                }
            }
        } message: {
            if let app = appPendingUninstall {
                Text("This moves \(app.name) and \(app.relatedFiles.count) related items to Trash. You can restore them from Finder.")
            }
        }
    }
}

private struct AppUninstallRow: View {
    let app: InstalledApp
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    if let version = app.version {
                        Text("v\(version)")
                    }
                    Text("\(app.relatedFiles.count) related files")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DiskWiseFormatters.bytes.string(fromByteCount: app.totalSize))
                    .font(.subheadline.monospacedDigit())
                Text("total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Uninstall", role: .destructive, action: onUninstall)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct OptimizePanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("System Optimization", systemImage: "gauge.with.dots.needle.67percent")
                .font(.title2.weight(.semibold))

            Text("Refresh services and clear diagnostic data. No permanent deletion unless noted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(viewModel.optimizationTasks, id: \.id) { task in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.body.weight(.medium))
                            Text(task.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Run") {
                            viewModel.runOptimizationTask(task)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if !viewModel.optimizationResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Results")
                        .font(.headline)
                    ForEach(viewModel.optimizationResults.indices, id: \.self) { index in
                        let result = viewModel.optimizationResults[index]
                        Label(result.message, systemImage: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(result.succeeded ? .green : .orange)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            viewModel.scanMaintenance(.optimize)
        }
    }
}

private struct SystemStatusPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("System Status", systemImage: "heart.text.square.fill")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    viewModel.refreshSystemSnapshot()
                }
            }

            if let snapshot = viewModel.systemSnapshot {
                healthHeader(snapshot)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    MetricCard(title: "CPU", icon: "cpu", value: String(format: "%.1f%%", snapshot.cpuUsagePercent), subtitle: "Load \(String(format: "%.2f", snapshot.loadAverage.one)) / \(snapshot.logicalCPUs) cores")
                    MetricCard(title: "Memory", icon: "memorychip", value: String(format: "%.1f%%", snapshot.memoryUsedPercent), subtitle: "\(DiskWiseFormatters.bytes.string(fromByteCount: snapshot.memoryUsed)) used")
                    MetricCard(title: "Disk", icon: "internaldrive", value: String(format: "%.1f%%", snapshot.diskUsedPercent), subtitle: "\(DiskWiseFormatters.bytes.string(fromByteCount: snapshot.diskFree)) free")
                    MetricCard(title: "Uptime", icon: "clock", value: snapshot.uptime, subtitle: snapshot.hardwareModel)
                }
                systemInfo(snapshot)
            } else {
                ProgressView("Loading system status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
        .padding(24)
    }

    private func healthHeader(_ snapshot: SystemSnapshot) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(snapshot.healthScore) / 100)
                    .stroke(healthColor(snapshot.healthScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(snapshot.healthScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 4) {
                Text(SystemHealthMonitorCore.healthConditionLabel(for: snapshot.healthScore))
                    .font(.headline)
                Text("Score \(snapshot.healthScore)/100")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(healthColor(snapshot.healthScore))
                Text(snapshot.hostName)
                    .font(.subheadline)
                Text(snapshot.osVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func healthColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .orange
        }
    }

    private func systemInfo(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Total memory").foregroundStyle(.secondary)
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: snapshot.memoryTotal))
                }
                GridRow {
                    Text("Disk capacity").foregroundStyle(.secondary)
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: snapshot.diskTotal))
                }
                GridRow {
                    Text("Load average").foregroundStyle(.secondary)
                    Text(String(format: "%.2f · %.2f · %.2f", snapshot.loadAverage.one, snapshot.loadAverage.five, snapshot.loadAverage.fifteen))
                }
            }
            .font(.caption)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
