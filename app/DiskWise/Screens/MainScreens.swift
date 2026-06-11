import SwiftUI
import DuplicateKit
import CleanupKit
import DatabaseKit

struct DuplicatesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedPreview: CleanupPreview?

    private var totalReclaimable: Int64 {
        viewModel.duplicateGroups.reduce(0) { $0 + $1.reclaimableSize }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !viewModel.duplicateGroups.isEmpty {
                    cleanupActionBar
                }

                if viewModel.isFindingDuplicates {
                    duplicateScanInProgress
                } else if viewModel.duplicateGroups.isEmpty {
                    duplicatesEmptyState
                } else {
                    howToCleanHint

                    ForEach(viewModel.duplicateGroups) { group in
                        DuplicateGroupCard(group: group) {
                            selectedPreview = viewModel.previewCleanup(for: group)
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(item: $selectedPreview) { preview in
            CleanupPreviewSheet(preview: preview) { result in
                if result.movedCount > 0 {
                    selectedPreview = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duplicate Files")
                .font(.largeTitle.bold())

            if totalReclaimable > 0 {
                Text("\(DiskWiseFormatters.bytes.string(fromByteCount: totalReclaimable)) reclaimable across \(viewModel.duplicateGroups.count) groups")
                    .font(.title3)
                    .foregroundStyle(.orange)
            } else if viewModel.isFindingDuplicates {
                Text("Still checking your drive for duplicate files…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Extra copies of the same file show up here after a scan")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cleanupActionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to free up space")
                    .font(.headline)
                Text("DiskWise keeps one copy per group and moves the rest to Trash. Empty Trash when you're sure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectedPreview = viewModel.previewAllDuplicatesCleanup()
            } label: {
                Label("Move All Duplicates to Trash", systemImage: "trash.fill")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
        }
        .padding(18)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var howToCleanHint: some View {
        Label("Use Move to Trash on any group below to remove extra copies safely.", systemImage: "hand.tap.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var duplicatesEmptyState: some View {
        if viewModel.hasScanData {
            ContentUnavailableView {
                Label("No duplicates found yet", systemImage: "doc.on.doc")
            } description: {
                Text("This drive has no duplicate file groups from the latest scan. Try rescanning after copying or downloading more files.")
            } actions: {
                if let volume = viewModel.selectedVolume {
                    Button("Rescan \(volume.name)") {
                        viewModel.scanSelectedVolume()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ContentUnavailableView(
                "Scan a drive first",
                systemImage: "externaldrive",
                description: Text("Select a drive in the sidebar and run a scan. Duplicate groups will appear in this tab.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private var duplicateScanInProgress: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress = viewModel.duplicateScanProgress {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(progress.level.label, systemImage: "doc.on.doc")
                            .font(.headline)
                        Text(progress.level.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress.levelFraction)
                        Text("\(progress.processedCount.formatted()) of \(progress.totalCount.formatted()) largest files checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Limit: \(viewModel.appSettings.duplicateScanFileLimit.formatted()) files · adjust in Settings (⌘,)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(progress.currentPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GroupBox {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing duplicate scan…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !viewModel.duplicateGroups.isEmpty {
                Text("Found so far")
                    .font(.headline)
                ForEach(viewModel.duplicateGroups) { group in
                    DuplicateGroupCard(group: group) {
                        selectedPreview = viewModel.previewCleanup(for: group)
                    }
                }
            } else {
                Text("Fingerprinting files can take several minutes on large drives. You can review storage in Overview while this runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    }
}

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let onCleanup: () -> Void

    private var displayName: String {
        if let first = group.files.first {
            return URL(fileURLWithPath: first.path).lastPathComponent
        }
        return group.fingerprint
    }

    private var extraCopyCount: Int {
        max(0, group.files.count - 1)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                        Text("\(group.files.count) copies · keep 1 · remove \(extraCopyCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(DiskWiseFormatters.bytes.string(fromByteCount: group.reclaimableSize)) reclaimable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.files.prefix(4), id: \.path) { file in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if group.files.count > 4 {
                        Text("+ \(group.files.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                Button(action: onCleanup) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Move \(extraCopyCount) Duplicate\(extraCopyCount == 1 ? "" : "s") to Trash")
                                .font(.headline)
                            Text("Keeps one copy · you can empty Trash later")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "trash.fill")
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AskDiskWiseView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private let suggestedQuestions = [
        "What is consuming most of my disk?",
        "Can I safely remove anything?",
        "Why is my SSD almost full?",
        "Find old videos I haven't watched.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ask DiskWise")
                                .font(.largeTitle.bold())
                            Text("Get storage insights powered by your scan data")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.aiResponses.isEmpty {
                            suggestedQuestionsSection
                        }

                        ForEach(viewModel.aiResponses) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(28)
                }
                .onChange(of: viewModel.aiResponses.count) { _, _ in
                    if let last = viewModel.aiResponses.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask about your storage…", text: $viewModel.aiQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.askAI(question: viewModel.aiQuestion)
                    }

                Button {
                    viewModel.askAI(question: viewModel.aiQuestion)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try asking:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        viewModel.askAI(question: question)
                    } label: {
                        Text(question)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.text)
                .font(.body)
                .padding(14)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

struct CleanupPreviewSheet: View {
    let preview: CleanupPreview
    let onConfirm: (CleanupResult) -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var failureMessage: String?
    @State private var showFailureAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Confirm cleanup", systemImage: "trash.fill")
                .font(.title.bold())
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(preview.items.count) duplicate file\(preview.items.count == 1 ? "" : "s") will move to Trash")
                    .font(.headline)
                Text("Frees \(DiskWiseFormatters.bytes.string(fromByteCount: preview.totalBytes)). Nothing is deleted permanently — empty Trash later when you're sure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            List(preview.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.subheadline.weight(.medium))
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    let result = viewModel.executeCleanup(preview: preview, revealTrash: true)
                    if result.movedCount > 0 {
                        onConfirm(result)
                        dismiss()
                    } else if let first = result.failures.first {
                        failureMessage = "\(URL(fileURLWithPath: first.path).lastPathComponent): \(first.reason)"
                        showFailureAlert = true
                    } else {
                        failureMessage = "No files were moved to Trash."
                        showFailureAlert = true
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 460)
        .alert("Could not move to Trash", isPresented: $showFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "DiskWise could not move these files to Trash.")
        }
    }
}

extension CleanupPreview: Identifiable {
    public var id: String {
        items.map(\.path).joined(separator: "|")
    }
}
