import SwiftUI

struct SystemMemoryReliefControl: View {
    @ObservedObject var monitor: SystemHealthMonitor
    let snapshot: SystemHealthSnapshot
    var compact: Bool = false
    var onStatusMessage: ((String) -> Void)?
    var trigger: Binding<Int>?

    @State private var isFreeingMemory = false
    @State private var memoryReliefMessage: String?

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                fullBody
            }
        }
        .background { triggerListener }
        .alert(
            "Memory Relief",
            isPresented: Binding(
                get: { memoryReliefMessage != nil },
                set: { if !$0 { memoryReliefMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(memoryReliefMessage ?? "")
        }
    }

    @ViewBuilder
    private var triggerListener: some View {
        if let trigger {
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: trigger.wrappedValue) { _, newValue in
                    guard newValue > 0 else { return }
                    Task { await freeUpMemory() }
                }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Memory", systemImage: "memorychip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%% used", snapshot.memoryUsedPercent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await freeUpMemory() }
            } label: {
                if isFreeingMemory {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Freeing memory…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Free Up Memory", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isFreeingMemory)
        }
    }

    private var fullBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "memorychip")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free Up Memory")
                            .font(.headline)
                        Text("Purge inactive RAM and disk caches to improve your memory headroom score. macOS may ask for your password to run purge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Label(
                        "\(String(format: "%.1f", snapshot.memoryUsedPercent))% used · \(MenuBarFormatters.gigabytes(snapshot.memoryUsedBytes)) active",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    freeUpMemoryButton
                }

                if snapshot.memoryUsedPercent >= 50 {
                    Text("Quitting apps under Top Memory can also raise your score when purge alone is not enough.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var freeUpMemoryButton: some View {
        Button {
            Task { await freeUpMemory() }
        } label: {
            if isFreeingMemory {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Free Up Memory", systemImage: "arrow.up.circle.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isFreeingMemory)
    }

    private func freeUpMemory() async {
        guard !isFreeingMemory else { return }
        isFreeingMemory = true
        defer { isFreeingMemory = false }

        let beforeScore = monitor.snapshot?.healthScore
        let result = await monitor.freeUpMemory()
        let afterScore = monitor.snapshot?.healthScore

        switch result {
        case .relieved(_, let message):
            onStatusMessage?("Memory freed")
            memoryReliefMessage = Self.scoreChangeMessage(
                base: message,
                beforeScore: beforeScore,
                afterScore: afterScore
            )
        case .improved(let message):
            onStatusMessage?("Memory pressure improved")
            memoryReliefMessage = Self.scoreChangeMessage(
                base: message,
                beforeScore: beforeScore,
                afterScore: afterScore
            )
        case .noMeasurableChange(let message):
            memoryReliefMessage = Self.scoreChangeMessage(
                base: message,
                beforeScore: beforeScore,
                afterScore: afterScore
            )
        case .requiresAdmin(let message):
            memoryReliefMessage = message
        case .failed(let message):
            memoryReliefMessage = message
        }
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
