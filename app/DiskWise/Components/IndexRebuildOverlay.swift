import SwiftUI

struct IndexRebuildOverlay: View {
    let version: String
    let onRebuild: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Rebuild storage index?")
                        .font(.title2.bold())
                    Text("DiskWise \(version) uses a new three-phase cleanup model. Your saved index was built with the previous pipeline and should be rebuilt for accurate recommendations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Identify disk usage on APFS volumes", systemImage: "1.circle.fill")
                    Label("Analyze into safe, review, and personal buckets", systemImage: "2.circle.fill")
                    Label("Take action via individual Maintenance tools", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.top, 4)

                HStack(spacing: 12) {
                    Button("Not Now") {
                        onSkip()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Rebuild Index") {
                        onRebuild()
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
