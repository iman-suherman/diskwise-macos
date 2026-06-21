import AppKit
import SwiftUI

private enum PendingMemoryReliefAction: Identifiable {
    case purge
    case quit(ProcessUsage)
    case restart

    var id: String {
        switch self {
        case .purge: return "purge"
        case .quit(let process): return "quit-\(process.id)"
        case .restart: return "restart"
        }
    }
}

struct SystemMemoryReliefControl: View {
    @ObservedObject var monitor: SystemHealthMonitor
    let snapshot: SystemHealthSnapshot
    var compact: Bool = false
    var onStatusMessage: ((String) -> Void)?
    /// Called before purge in menu bar popover so the panel can dismiss before auth dialogs.
    var onWillFreeMemory: (() -> Void)?
    var trigger: Binding<Int>?

    @State private var isPerformingAction = false
    @State private var memoryReliefMessage: String?
    @State private var pendingAction: PendingMemoryReliefAction?

    private var assessment: MemoryPressureAssessment {
        snapshot.memoryPressureAssessment
    }

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                fullBody
            }
        }
        .background { triggerListener }
        .modifier(MemoryReliefResultAlert(message: $memoryReliefMessage, enabled: !compact))
        .alert(item: $pendingAction) { action in
            reliefConfirmationAlert(for: action)
        }
    }

    @ViewBuilder
    private var triggerListener: some View {
        if let trigger {
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: trigger.wrappedValue) { _, newValue in
                    guard newValue > 0 else { return }
                    queuePrimaryAction()
                }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            memoryPressureHeader

            if let symptom = assessment.symptomDetail {
                Text(symptom)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryActionButton
        }
    }

    private var fullBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                memoryPressureHeader

                Text(assessment.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let symptom = assessment.symptomDetail {
                    Label(symptom, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(severityColor(assessment.severity))
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                }

                memoryMetricsRow

                if !assessment.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested next step")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(assessment.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Label(suggestion, systemImage: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Spacer()
                    primaryActionButton
                    if assessment.reliefTier > .purgeCache {
                        secondaryPurgeButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Memory Pressure", systemImage: "memorychip")
        }
    }

    private var memoryPressureHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(assessment.severity.label, systemImage: "gauge.with.dots.needle.67percent")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(severityColor(assessment.severity))

            Spacer()

            Text(assessment.reliefTier.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var memoryMetricsRow: some View {
        HStack(spacing: 16) {
            metricChip(
                title: "Free RAM",
                value: MenuBarFormatters.gigabytes(assessment.metrics.pagesFreeBytes)
            )
            metricChip(
                title: "Swap",
                value: swapLabel
            )
            metricChip(
                title: "Compressed",
                value: MenuBarFormatters.gigabytes(assessment.metrics.compressedBytes)
            )
        }
    }

    private var swapLabel: String {
        guard assessment.metrics.swapTotalBytes > 0 else { return "—" }
        return "\(MenuBarFormatters.gigabytes(assessment.metrics.swapUsedBytes)) (\(String(format: "%.0f", assessment.metrics.swapUsedPercent))%)"
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

  private var primaryActionButton: some View {
        Button {
            queuePrimaryAction()
        } label: {
            if isPerformingAction {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(actionProgressLabel)
                }
                .frame(maxWidth: compact ? .infinity : nil)
            } else {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
                    .frame(maxWidth: compact ? .infinity : nil)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .small : .regular)
        .disabled(isPerformingAction || assessment.reliefTier == .none)
    }

    private var secondaryPurgeButton: some View {
        Button {
            pendingAction = .purge
        } label: {
            Label("Purge Cache", systemImage: "arrow.up.circle")
        }
        .buttonStyle(.bordered)
        .disabled(isPerformingAction)
    }

    private var primaryActionTitle: String {
        switch assessment.reliefTier {
        case .none:
            return "Memory OK"
        case .purgeCache:
            return "Free Up Memory"
        case .quitApps:
            if let target = assessment.recommendedQuitTarget {
                return "Quit \(target.name)"
            }
            return "Review Heavy Apps"
        case .reboot:
            return "Restart Mac…"
        }
    }

    private var primaryActionIcon: String {
        switch assessment.reliefTier {
        case .none: return "checkmark.circle"
        case .purgeCache: return "arrow.up.circle.fill"
        case .quitApps: return "xmark.app.fill"
        case .reboot: return "arrow.clockwise.circle.fill"
        }
    }

    private var actionProgressLabel: String {
        switch pendingAction ?? inferredPendingFromTier() {
        case .purge, .none: return "Freeing memory…"
        case .quit: return "Quitting app…"
        case .restart: return "Requesting restart…"
        }
    }

    private func inferredPendingFromTier() -> PendingMemoryReliefAction? {
        switch assessment.reliefTier {
        case .purgeCache: return .purge
        case .quitApps:
            if let target = assessment.recommendedQuitTarget {
                return .quit(target)
            }
            return nil
        case .reboot: return .restart
        case .none: return nil
        }
    }

    private func queuePrimaryAction() {
        switch assessment.reliefTier {
        case .none:
            return
        case .purgeCache:
            pendingAction = .purge
        case .quitApps:
            if let target = assessment.recommendedQuitTarget {
                pendingAction = .quit(target)
            } else {
                memoryReliefMessage = "Open Top Memory below and quit apps you are not using."
            }
        case .reboot:
            pendingAction = .restart
        }
    }

  private func reliefConfirmationAlert(for action: PendingMemoryReliefAction) -> Alert {
        switch action {
        case .purge:
            return Alert(
                title: Text("Free inactive memory?"),
                message: Text(purgeConfirmationMessage),
                primaryButton: .default(Text("Free Memory")) {
                    Task { await performReliefAction(.purge) }
                },
                secondaryButton: .cancel {
                    pendingAction = nil
                }
            )
        case .quit(let process):
            return Alert(
                title: Text("Quit \(process.name)?"),
                message: Text(quitConfirmationMessage(for: process)),
                primaryButton: .destructive(Text("Quit")) {
                    Task { await performReliefAction(.quit(process)) }
                },
                secondaryButton: .cancel {
                    pendingAction = nil
                }
            )
        case .restart:
            return Alert(
                title: Text("Restart your Mac?"),
                message: Text(restartConfirmationMessage),
                primaryButton: .default(Text("Restart…")) {
                    Task { await performReliefAction(.restart) }
                },
                secondaryButton: .cancel {
                    pendingAction = nil
                }
            )
        }
    }

    private var purgeConfirmationMessage: String {
        if assessment.reliefTier >= .quitApps {
            return "Purging inactive cache may help slightly, but \(MenuBarFormatters.gigabytes(assessment.metrics.swapUsedBytes)) swap is in use — quitting heavy apps or restarting will restore performance faster."
        }
        return "Runs purge to reclaim inactive RAM and disk caches. macOS may ask for your password."
    }

    private func quitConfirmationMessage(for process: ProcessUsage) -> String {
        let size = MenuBarFormatters.compactFreeSpace(process.memoryBytes)
        let cpu = String(format: "%.0f", process.cpuPercent)
        var message = "\(process.name) is using \(size) and \(cpu)% CPU. Quitting frees RAM immediately."
        if assessment.windowServerStressed {
            message += " This should reduce system-wide input lag."
        }
        message += " Unsaved work may be lost."
        return message
    }

    private var restartConfirmationMessage: String {
        var parts = [
            "Swap has grown to \(MenuBarFormatters.gigabytes(assessment.metrics.swapUsedBytes)) (\(String(format: "%.0f", assessment.metrics.swapUsedPercent))% of swap file).",
            "A restart clears swap and the memory compressor — the most reliable way to end sluggishness when RAM is exhausted.",
        ]
        if assessment.recommendedQuitTarget != nil {
            parts.append("You can quit heavy apps first for a quicker interim fix.")
        }
        return parts.joined(separator: " ")
    }

    private func performReliefAction(_ action: PendingMemoryReliefAction) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        pendingAction = nil
        defer { isPerformingAction = false }

        let beforeScore = monitor.snapshot?.healthScore
        let message: String

        switch action {
        case .purge:
            if compact {
                await MainActor.run { onWillFreeMemory?() }
            }
            let result = await monitor.freeUpMemory()
            message = resultMessage(
                for: result,
                beforeScore: beforeScore,
                afterScore: monitor.snapshot?.healthScore
            )
        case .quit(let process):
            let quitMessage = await MemoryActionExecutor.perform(
                kind: .quitProcess,
                targetProcessName: process.name
            )
            monitor.refreshDetailed()
            onStatusMessage?("Quit \(process.name)")
            message = quitMessage
        case .restart:
            let restarted = await MainActor.run { SystemHealthMonitorCore.requestSystemRestart() }
            message = restarted
                ? "macOS restart confirmation should appear. Save your work before confirming."
                : "Could not show the restart dialog. Use Apple menu → Restart manually."
        }

        if compact {
            await MainActor.run { Self.presentMemoryReliefAlert(message) }
        } else {
            memoryReliefMessage = message
        }
    }

    private func resultMessage(
        for result: MemoryReliefResult,
        beforeScore: Int?,
        afterScore: Int?
    ) -> String {
        switch result {
        case .relieved(_, let message):
            onStatusMessage?("Memory freed")
            return Self.scoreChangeMessage(base: message, beforeScore: beforeScore, afterScore: afterScore)
        case .improved(let message):
            onStatusMessage?("Memory pressure improved")
            return Self.scoreChangeMessage(base: message, beforeScore: beforeScore, afterScore: afterScore)
        case .noMeasurableChange(let message):
            return Self.scoreChangeMessage(base: message, beforeScore: beforeScore, afterScore: afterScore)
        case .requiresAdmin(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    private func severityColor(_ severity: MemoryPressureSeverity) -> Color {
        let rgb = severity.activityMonitorColor
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    @MainActor
    private static func presentMemoryReliefAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Memory Relief"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func scoreChangeMessage(base: String, beforeScore: Int?, afterScore: Int?) -> String {
        guard let beforeScore, let afterScore else { return base }
        if afterScore > beforeScore {
            return "\(base)\n\nHealth score improved from \(beforeScore) to \(afterScore)."
        }
        if afterScore < beforeScore {
            return "\(base)\n\nHealth score is now \(afterScore) (was \(beforeScore))."
        }
        return "\(base)\n\nHealth score remains \(afterScore)."
    }
}

private struct MemoryReliefResultAlert: ViewModifier {
    @Binding var message: String?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.alert(
                "Memory Relief",
                isPresented: Binding(
                    get: { message != nil },
                    set: { if !$0 { message = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        } else {
            content
        }
    }
}
