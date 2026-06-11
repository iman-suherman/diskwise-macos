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

    init(state: RecommendationReviewState) {
        _reviewState = State(initialValue: state)
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
                selectionToolbar

                List(reviewState.files, id: \.path) { file in
                    RecommendationFileRow(
                        file: file,
                        isSelected: file.id.map { reviewState.selectedFileIDs.contains($0) } ?? false,
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewState.recommendation.title)
                .font(.title.bold())

            Text(reviewState.recommendation.reason)
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

            Button("Move Selected to Trash", role: .destructive) {
                viewModel.executeRecommendationCleanup(
                    files: selectedFiles,
                    recommendation: reviewState.recommendation
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
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
}

private struct RecommendationFileRow: View {
    let file: FileRecord
    let isSelected: Bool
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
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
