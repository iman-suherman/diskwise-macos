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
                    Text("Menu bar disk monitor")
                        .font(.title2.bold())
                    Text("DiskWise shows remaining disk space in the menu bar while the app is running.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                instructionRow(
                    number: 1,
                    title: "Look for the icon",
                    detail: "The percentage and bar show free space. Red means less than twice your Mac’s memory is available."
                )
                instructionRow(
                    number: 2,
                    title: "Click for details",
                    detail: "Click the menu bar icon to see used space, total capacity, and free space for your startup disk."
                )
                instructionRow(
                    number: 3,
                    title: "Toggle anytime",
                    detail: "Use View → Show Disk Space in Menu Bar, Settings, or Hide Menu Bar Monitor in the popover to turn it off."
                )
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
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
