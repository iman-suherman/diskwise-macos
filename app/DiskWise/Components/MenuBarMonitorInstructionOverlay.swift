import SwiftUI

struct MenuBarMonitorInstructionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up menu bar disk monitor")
                        .font(.title2.bold())
                    Text("DiskWise shows Macintosh HD usage in the menu bar while the app is running.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(
                    number: 1,
                    title: "Menu bar monitor is on",
                    detail: "Look for the percentage and bar chart in the top menu bar while DiskWise is open."
                )
                instructionRow(
                    number: 2,
                    title: "Approve login at startup",
                    detail: "In System Settings → General → Login Items → Open at Login, turn on DiskWise so the monitor starts when you log in."
                )
                instructionRow(
                    number: 3,
                    title: "Use the View menu",
                    detail: "You can also toggle “Show Disk Space in Menu Bar” from View in the menu bar."
                )
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Button("Open System Settings") {
                    MenuBarMonitorController.openLoginItemsSettingsForApproval()
                }

                Spacer()

                Button("Got It") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func instructionRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
