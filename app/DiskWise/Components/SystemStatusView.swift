import AppKit
import SwiftUI

struct SystemStatusView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var monitor = SystemHealthMonitor.shared

    @State private var selectedProcess: ProcessDetail?
    @State private var terminateRequest: ProcessTerminateRequest?
    @State private var terminateResultMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let snapshot = monitor.snapshot {
                    scoreCard(snapshot)
                    metricsCard(snapshot)
                    systemDetailsCard(snapshot)

                    HStack(alignment: .top, spacing: 20) {
                        processCard(
                            title: "Top CPU",
                            icon: "cpu",
                            processes: snapshot.topCPUProcesses,
                            value: { String(format: "%.1f%%", $0.cpuPercent) }
                        )
                        processCard(
                            title: "Top Memory",
                            icon: "memorychip",
                            processes: snapshot.topMemoryProcesses,
                            value: { MenuBarFormatters.gigabytes($0.memoryBytes) }
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "System status unavailable",
                        systemImage: "heart.text.square",
                        description: Text("Could not read CPU, memory, or process metrics.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(28)
        }
        .onAppear {
            monitor.refreshDetailed()
        }
        .onDisappear {
            monitor.refresh(processLimit: 5)
        }
        .sheet(item: $selectedProcess) { process in
            ProcessDetailSheet(
                process: process,
                onQuit: { terminateRequest = ProcessTerminateRequest(process: process, force: false) },
                onForceQuit: { terminateRequest = ProcessTerminateRequest(process: process, force: true) }
            )
        }
        .alert(
            terminateRequest?.force == true ? "Force Quit Process?" : "Quit Process?",
            isPresented: Binding(
                get: { terminateRequest != nil },
                set: { if !$0 { terminateRequest = nil } }
            ),
            presenting: terminateRequest
        ) { request in
            Button(request.force ? "Force Quit" : "Quit", role: .destructive) {
                terminate(request)
            }
            Button("Cancel", role: .cancel) {
                terminateRequest = nil
            }
        } message: { request in
            if request.process.pid == ProcessInfo.processInfo.processIdentifier {
                Text("Quitting \(request.process.name) will close DiskWise.")
            } else {
                Text("Send \(request.force ? "SIGKILL to" : "quit signal to") \(request.process.name) (PID \(request.process.pid))?")
            }
        }
        .alert(
            "Process Action",
            isPresented: Binding(
                get: { terminateResultMessage != nil },
                set: { if !$0 { terminateResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(terminateResultMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Status")
                    .font(.largeTitle.bold())
                Text("Live CPU, memory, and process metrics for this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                monitor.refreshDetailed()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func scoreCard(_ snapshot: SystemHealthSnapshot) -> some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(SystemHealthMonitorCore.healthConditionLabelWithScore(for: snapshot.healthScore))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(snapshot.healthScore))

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.hostName)
                        .font(.title3.weight(.semibold))
                    Text("\(snapshot.machineModel) · macOS \(snapshot.macOSVersion) (\(snapshot.macOSBuild))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func metricsCard(_ snapshot: SystemHealthSnapshot) -> some View {
        GroupBox {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                metricTile(title: "CPU", value: String(format: "%.1f%%", snapshot.cpuUsagePercent), icon: "cpu")
                metricTile(title: "Memory", value: String(format: "%.1f%%", snapshot.memoryUsedPercent), icon: "memorychip")
                metricTile(title: "Disk", value: String(format: "%.1f%%", snapshot.diskUsedPercent), icon: "internaldrive")
                metricTile(title: "Uptime", value: formatUptime(snapshot.uptimeSeconds), icon: "clock")
            }
        }
    }

    @ViewBuilder
    private func systemDetailsCard(_ snapshot: SystemHealthSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                detailRow("Load average", String(format: "%.2f · %.2f · %.2f", snapshot.loadAverage1, snapshot.loadAverage5, snapshot.loadAverage15))
                detailRow("Processor cores", "\(snapshot.processorCount)")
                detailRow("Memory used", MenuBarFormatters.gigabytes(snapshot.memoryUsedBytes))
                detailRow("Physical memory", MenuBarFormatters.gigabytes(snapshot.physicalMemoryBytes))
                detailRow("Disk free", MenuBarFormatters.gigabytes(snapshot.diskFreeBytes))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    @ViewBuilder
    private func processCard(
        title: String,
        icon: String,
        processes: [ProcessUsage],
        value: @escaping (ProcessUsage) -> String
    ) -> some View {
        GroupBox {
            if processes.isEmpty {
                Text("No process data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        Button {
                            selectedProcess = SystemHealthMonitorCore.inspectProcess(process)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(process.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("PID \(process.id)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(value(process))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < processes.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Label(title, systemImage: icon)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func metricTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }

    private func scoreColor(_ score: Int) -> Color {
        let rgb = SystemHealthMonitorCore.healthScoreColor(score)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
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

    private func terminate(_ request: ProcessTerminateRequest) {
        let result = SystemHealthMonitorCore.terminateProcess(pid: request.process.pid, force: request.force)
        terminateRequest = nil
        selectedProcess = nil

        switch result {
        case .terminated:
            viewModel.reportProcessAction(
                request.force ? "Force quit \(request.process.name)" : "Quit \(request.process.name)"
            )
            monitor.refreshDetailed()
        case .permissionDenied:
            terminateResultMessage = "DiskWise does not have permission to quit \(request.process.name). Try Activity Monitor or run with appropriate privileges."
        case .processNotFound:
            terminateResultMessage = "\(request.process.name) is no longer running."
            monitor.refreshDetailed()
        case .protectedSystemProcess:
            terminateResultMessage = "System processes cannot be quit from DiskWise."
        case .failed(let message):
            terminateResultMessage = message
        }
    }
}

private struct ProcessDetailSheet: View {
    let process: ProcessDetail
    let onQuit: () -> Void
    let onForceQuit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "app.dashed")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(process.name)
                        .font(.title2.bold())
                    Text(process.isRunning ? "Running · PID \(process.pid)" : "Not running · PID \(process.pid)")
                        .font(.subheadline)
                        .foregroundStyle(process.isRunning ? Color.secondary : Color.orange)
                }

                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                detailGridRow("CPU", String(format: "%.1f%%", process.cpuPercent))
                detailGridRow("Memory", MenuBarFormatters.gigabytes(process.memoryBytes))
                if let owner = process.ownerUsername {
                    detailGridRow("Owner", owner)
                }
                if let parentPID = process.parentPID {
                    detailGridRow("Parent PID", "\(parentPID)")
                }
                if let bundleIdentifier = process.bundleIdentifier {
                    detailGridRow("Bundle ID", bundleIdentifier)
                }
            }

            if let path = process.executablePath {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Executable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Quit Process") {
                    onQuit()
                    dismiss()
                }
                .disabled(!process.isRunning || process.pid <= 1)

                Button("Force Quit") {
                    onForceQuit()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!process.isRunning || process.pid <= 1)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
    }

    private func detailGridRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}
