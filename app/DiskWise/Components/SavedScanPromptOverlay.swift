import SwiftUI

struct SavedScanPromptOverlay: View {
    let volumeName: String
    let onLoadSaved: () -> Void
    let onRebuild: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Load saved scan for \(volumeName)?")
                        .font(.title2.bold())
                    Text("DiskWise found a previous scan for this drive. Load it to explore storage right away, or rebuild with a fresh scan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                HStack(spacing: 12) {
                    Button("Not Now") {
                        onSkip()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Rebuild Scan") {
                        onRebuild()
                    }

                    Button("Load Saved Scan") {
                        onLoadSaved()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(40)
        }
        .transition(.opacity)
        .zIndex(101)
    }
}
