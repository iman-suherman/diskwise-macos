import SwiftUI
import AppKit

struct ActivityLogView: View {
    @ObservedObject var activityLog: ActivityLog
    var embeddedInPanel: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var copiedConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            toolbar

            if activityLog.entries.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Scan a drive or run cleanup to populate the log.")
                )
                .frame(maxWidth: .infinity, minHeight: embeddedInPanel ? 320 : nil)
                .frame(maxHeight: embeddedInPanel ? .infinity : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(activityLog.entries.reversed()) { entry in
                            ActivityLogRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxHeight: embeddedInPanel ? .infinity : nil)
            }
        }
        .padding(embeddedInPanel ? 0 : 24)
        .frame(
            minWidth: embeddedInPanel ? nil : 720,
            minHeight: embeddedInPanel ? nil : 520
        )
        .frame(maxWidth: embeddedInPanel ? .infinity : nil, maxHeight: embeddedInPanel ? .infinity : nil, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        if embeddedInPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity Log")
                    .font(.largeTitle.bold())
                Text("Recent scan, cleanup, and error events. Share this with support when reporting an issue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Log")
                        .font(.title.bold())
                    Text("Recent scan, cleanup, and error events. Share this with support when reporting an issue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") { dismiss() }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                copyToPasteboard()
            } label: {
                Label(copiedConfirmation ? "Copied" : "Copy Log", systemImage: copiedConfirmation ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                saveToFile()
            } label: {
                Label("Save Log…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Button("Clear") {
                activityLog.clear()
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(activityLog.entries.count.formatted()) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activityLog.exportText(), forType: .string)
        copiedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedConfirmation = false
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.title = "Save Activity Log"
        panel.nameFieldStringValue = "diskwise-activity-\(exportStamp()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? activityLog.exportText().write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct ActivityLogRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.category.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(categoryTint.opacity(0.15), in: Capsule())
                    .foregroundStyle(categoryTint)

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()
            }

            Text(entry.message)
                .font(.subheadline.weight(.medium))

            if let detail = entry.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private var categoryTint: Color {
        switch entry.category {
        case .scan: return .blue
        case .duplicate: return .purple
        case .cleanup: return .orange
        case .recommendation: return .green
        case .system: return .secondary
        }
    }
}
