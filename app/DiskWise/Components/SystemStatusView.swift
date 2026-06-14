import AppKit
import SwiftUI

struct SystemStatusView: View {
    var embeddedInOptimization: Bool = false

    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var monitor = SystemHealthMonitor.shared

    @State private var selectedProcess: ProcessDetail?
    @State private var terminateRequest: ProcessTerminateRequest?
    @State private var terminateResultMessage: String?
    @State private var memoryReliefTrigger = 0

    var body: some View {
        Group {
            if embeddedInOptimization {
                embeddedContent
            } else {
                ScrollView {
                    embeddedContent
                        .padding(28)
                }
            }
        }
        .onAppear {
            guard !embeddedInOptimization else { return }
            monitor.refreshDetailed()
        }
        .onDisappear {
            guard !embeddedInOptimization else { return }
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

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !embeddedInOptimization {
                header
            } else {
                sectionHeading("System Status", icon: "heart.text.square", detail: "Live CPU, memory, and process metrics for this Mac.")
            }

            if let snapshot = monitor.snapshot {
                scoreCard(snapshot)
                metricsCard(snapshot)
                SystemMemoryReliefControl(
                    monitor: monitor,
                    snapshot: snapshot,
                    onStatusMessage: { viewModel.reportProcessAction($0) },
                    trigger: $memoryReliefTrigger
                )
                systemDetailsCard(snapshot)

                HStack(alignment: .top, spacing: 20) {
                    cpuProcessCard(snapshot)
                    memoryProcessCard(snapshot)
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
    }

    private func sectionHeading(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.title2.bold())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

            if monitor.snapshot != nil {
                Button {
                    memoryReliefTrigger += 1
                } label: {
                    Label("Free Up Memory", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }

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
        let explanation = SystemHealthMonitorCore.explainHealthScore(for: snapshot)

        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("What this score means")
                        .font(.subheadline.weight(.semibold))

                    Text(explanation.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    healthLabelLegend(explanation)

                    healthFormulaSection(explanation)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(explanation.factors.enumerated()), id: \.offset) { _, factor in
                            healthFactorRow(factor)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if !explanation.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(Array(explanation.recommendations.enumerated()), id: \.offset) { _, recommendation in
                                Label(recommendation, systemImage: "lightbulb")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func healthLabelLegend(_ explanation: HealthScoreExplanation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating scale")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(explanation.labelBands) { band in
                    HStack(alignment: .top, spacing: 10) {
                        Text(band.label)
                            .font(.caption.weight(band.label == explanation.label ? .bold : .semibold))
                            .foregroundStyle(
                                band.label == explanation.label
                                    ? scoreColor(explanation.score)
                                    : Color.secondary
                            )
                            .frame(width: 44, alignment: .leading)

                        Text(band.rangeDescription)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)

                        Text(band.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        band.label == explanation.label
                            ? scoreColor(explanation.score).opacity(0.1)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func healthFormulaSection(_ explanation: HealthScoreExplanation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How \(explanation.label) (\(explanation.score)) is calculated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(explanation.formulaDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(explanation.formulaSteps.enumerated()), id: \.offset) { _, step in
                    Text(step)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func healthFactorRow(_ factor: HealthScoreFactor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(factor.statusLabel) · \(String(format: "%.1f", factor.usagePercent))% used")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(factor.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Component score \(factor.componentScore)/100 · \(factor.weightPercent)% of overall score")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func cpuProcessCard(_ snapshot: SystemHealthSnapshot) -> some View {
        let significant = SystemHealthMonitorCore.significantCPUProcesses(snapshot.topCPUProcesses)
        processCard(
            title: "Top CPU",
            icon: "cpu",
            processes: significant,
            emptyMessage: SystemHealthMonitorCore.idleCPUMessage(for: snapshot),
            emptyIcon: "cpu",
            value: { String(format: "%.1f%%", $0.cpuPercent) }
        )
    }

    @ViewBuilder
    private func memoryProcessCard(_ snapshot: SystemHealthSnapshot) -> some View {
        let significant = SystemHealthMonitorCore.significantMemoryProcesses(snapshot.topMemoryProcesses)
        processCard(
            title: "Top Memory",
            icon: "memorychip",
            processes: significant,
            emptyMessage: SystemHealthMonitorCore.idleMemoryMessage(for: snapshot),
            emptyIcon: "memorychip",
            value: { MenuBarFormatters.gigabytes($0.memoryBytes) }
        )
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
        emptyMessage: String,
        emptyIcon: String,
        value: @escaping (ProcessUsage) -> String
    ) -> some View {
        GroupBox {
            if processes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No significant usage right now", systemImage: emptyIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                explanationSection

                usageSection

                ownershipSection

                technicalSection

                actionBar
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            processIcon
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(process.name)
                    .font(.title2.bold())

                HStack(spacing: 8) {
                    Text(process.category.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())

                    Text(process.isRunning ? "Running · PID \(process.pid)" : "Not running · PID \(process.pid)")
                        .font(.subheadline)
                        .foregroundStyle(process.isRunning ? Color.secondary : Color.orange)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var processIcon: some View {
        if let app = NSRunningApplication(processIdentifier: process.pid),
           let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: iconName(for: process.category))
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is this process?")
                .font(.subheadline.weight(.semibold))

            Text(process.roleSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let applicationName = process.applicationName, applicationName != process.name {
                detailCallout(title: "Application", value: applicationName)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var usageSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            detailGridRow("CPU", String(format: "%.1f%%", process.cpuPercent))
            detailGridRow("Memory", MenuBarFormatters.gigabytes(process.memoryBytes))
        }
    }

    private var ownershipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ownership")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                if let owner = process.ownerUsername {
                    detailGridRow("Owner", owner)
                }
                if let parentName = process.parentName, let parentPID = process.parentPID {
                    detailGridRow("Started by", "\(parentName) (PID \(parentPID))")
                } else if let parentPID = process.parentPID {
                    detailGridRow("Parent PID", "\(parentPID)")
                }
                if let bundleIdentifier = process.bundleIdentifier {
                    detailGridRow("Bundle ID", bundleIdentifier)
                }
            }
        }
    }

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Technical details")
                .font(.subheadline.weight(.semibold))

            if let commandLine = process.commandLine {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(commandLine)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    private var actionBar: some View {
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

    private func detailCallout(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func iconName(for category: ProcessCategory) -> String {
        switch category {
        case .userApplication:
            return "app.fill"
        case .systemService:
            return "gearshape.2.fill"
        case .shell:
            return "terminal.fill"
        case .backgroundAgent:
            return "arrow.triangle.2.circlepath"
        case .commandLineTool:
            return "hammer.fill"
        case .unknown:
            return "app.dashed"
        }
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
