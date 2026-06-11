import SwiftUI
import AppKit
import DatabaseKit
import CleanupKit

struct RecommendationReviewState: Identifiable {
    let id = UUID()
    let recommendation: RecommendationRecord
    let files: [FileRecord]
    var selectedFileIDs: Set<Int64>
}

struct RecommendationReviewSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reviewState: RecommendationReviewState
    @State private var cleanupAlertMessage: String?
    @State private var showCleanupAlert = false

    init(state: RecommendationReviewState) {
        _reviewState = State(initialValue: state)
    }

    private var isDMGReview: Bool {
        reviewState.recommendation.type == "delete_dmg"
    }

    private var isArchiveOldVideosReview: Bool {
        reviewState.recommendation.type == "archive_old_files"
    }

    private var selectedFiles: [FileRecord] {
        reviewState.files.filter { file in
            guard let id = file.id else { return false }
            return reviewState.selectedFileIDs.contains(id)
        }
    }

    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if reviewState.files.isEmpty {
                ContentUnavailableView(
                    "No matching files",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Rescan the drive if you expected files here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if isDMGReview {
                    dmgGuidanceBanner
                } else if isArchiveOldVideosReview {
                    archiveVideosGuidanceBanner
                }

                selectionToolbar

                List(reviewState.files, id: \.path) { file in
                    RecommendationFileRow(
                        file: file,
                        isSelected: file.id.map { reviewState.selectedFileIDs.contains($0) } ?? false,
                        classification: RemovablePathRules.classifyInstallerArtifact(path: file.path, size: file.size),
                        onToggle: { toggle(file) },
                        onReveal: { reveal(file) }
                    )
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 520)
        .alert("Could not move to Trash", isPresented: $showCleanupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanupAlertMessage ?? "DiskWise could not move the selected files to Trash.")
        }
    }

    private var recommendationSubtitle: String {
        if isDMGReview {
            return "Shows installer files in Downloads, Desktop, and Documents — not macOS system images under /System/Library."
        }
        if isArchiveOldVideosReview {
            return "Video files (.mp4, .mov, etc.) in your home folder that have not been opened recently."
        }
        return reviewState.recommendation.reason
    }

    private var archiveVideosGuidanceBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What counts as a video", systemImage: "film")
                .font(.subheadline.weight(.semibold))

            Text("Only files with a video extension (.mp4, .mov, .mkv, and similar) under your user folder are listed. System assets, artwork, and other file types are excluded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var dmgGuidanceBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to clean safely", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Only delete installer files from Downloads, Desktop, or Documents. Leave Preboot, system folders, and anything outside those locations alone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Small app.dmg installers are usually safe after installation. Review os.dmg and os.clone.dmg carefully. Reveal in Finder first, move to Trash, restart, then empty Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewState.recommendation.title)
                .font(.title.bold())

            Text(recommendationSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(
                    "\(reviewState.files.count.formatted()) files",
                    systemImage: "doc.on.doc"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Potential savings: \(DiskWiseFormatters.bytes.string(fromByteCount: reviewState.recommendation.estimatedSavings))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedFiles.count.formatted()) selected · \(DiskWiseFormatters.bytes.string(fromByteCount: selectedBytes))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            if isDMGReview {
                Button("Select Safe Only") {
                    reviewState.selectedFileIDs = Set(
                        reviewState.files.compactMap { file in
                            guard let id = file.id else { return nil }
                            let classification = RemovablePathRules.classifyInstallerArtifact(path: file.path, size: file.size)
                            return classification?.selectedByDefault == true ? id : nil
                        }
                    )
                }
                .buttonStyle(.borderless)
            }

            Button("Select All") {
                reviewState.selectedFileIDs = Set(reviewState.files.compactMap(\.id))
            }
            .buttonStyle(.borderless)

            Button("Clear") {
                reviewState.selectedFileIDs = []
            }
            .buttonStyle(.borderless)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                viewModel.dismissRecommendationReview()
                dismiss()
            }

            Spacer()

            Button {
                let result = viewModel.executeRecommendationCleanup(
                    files: selectedFiles,
                    recommendation: reviewState.recommendation
                )
                if result.movedCount > 0 {
                    dismiss()
                } else {
                    cleanupAlertMessage = cleanupFailureMessage(for: result)
                    showCleanupAlert = true
                }
            } label: {
                Label("Move Selected to Trash", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .disabled(selectedFiles.isEmpty)
        }
    }

    private func toggle(_ file: FileRecord) {
        guard let id = file.id else { return }
        if reviewState.selectedFileIDs.contains(id) {
            reviewState.selectedFileIDs.remove(id)
        } else {
            reviewState.selectedFileIDs.insert(id)
        }
    }

    private func reveal(_ file: FileRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    private func cleanupFailureMessage(for result: CleanupResult) -> String {
        if let first = result.failures.first {
            let name = URL(fileURLWithPath: first.path).lastPathComponent
            return "\(name): \(first.reason)"
        }
        return "No files were moved to Trash. Try granting Full Disk Access, then rescan and try again."
    }
}

private struct RecommendationFileRow: View {
    let file: FileRecord
    let isSelected: Bool
    let classification: DMGFileClassification?
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
                HStack(spacing: 8) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if let classification {
                        DMGSafetyBadge(classification: classification)
                    }
                }

                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let classification {
                    Text(classification.detail)
                        .font(.caption2)
                        .foregroundStyle(classification.level == .cautionOSImage ? .orange : .secondary)
                        .lineLimit(2)
                } else if let reason = CleanupEngine.canTrashFile(atPath: file.path).reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text(DiskWiseFormatters.bytes.string(fromByteCount: file.size))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: onReveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
    }
}

private struct DMGSafetyBadge: View {
    let classification: DMGFileClassification

    var body: some View {
        Text(classification.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor.opacity(0.15), in: Capsule())
            .foregroundStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        switch classification.level {
        case .safeInstaller: return .green
        case .appleDownloadArtifact: return .blue
        case .cautionOSImage: return .orange
        }
    }
}
