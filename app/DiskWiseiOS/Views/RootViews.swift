import PhotosKit
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let route = model.demoRoute {
                    demoScreen(for: route)
                } else if !model.canScan {
                    PermissionView()
                } else {
                    DashboardView()
                }
            }
            .navigationTitle(demoNavigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.canScan, model.demoRoute == nil || model.demoRoute == .dashboard {
                        Button {
                            Task { await model.scan() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isScanning || model.isCleaning)
                        .accessibilityLabel("Rescan library")
                    }
                }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func demoScreen(for route: DemoScreenshotRoute) -> some View {
        switch route {
        case .dashboard:
            DashboardView()
        case .recommendations:
            // Must be visually distinct from dashboard (App Review 2.3.3).
            if let summary = model.demoRecommendationSummary {
                BucketDetailView(summary: summary)
            } else {
                DashboardView()
            }
        case .bucket:
            if let summary = model.demoBucketSummary {
                BucketDetailView(summary: summary)
            } else {
                DashboardView()
            }
        case .confirm:
            ReviewCleanupView()
        }
    }

    private var demoNavigationTitle: String {
        switch model.demoRoute {
        case .recommendations:
            return model.demoRecommendationSummary?.bucket.title ?? "Large Videos"
        case .bucket:
            return model.demoBucketSummary?.bucket.title ?? "Screenshots"
        case .confirm:
            return "Confirm cleanup"
        case .dashboard, .none:
            return "DiskWise"
        }
    }
}

struct PermissionView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Photos storage consultant")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(
                "DiskWise analyzes your photo library on this device, finds reclaimable space, and moves selected items to Recently Deleted — never permanently deletes in v1."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            if model.authorization == .denied || model.authorization == .restricted {
                Text("Photo access is off. Enable it in Settings → DiskWise → Photos.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Continue") {
                    Task { await model.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .padding()
        .onAppear { model.refreshAuthorization() }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reclaimable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormat.string(for: model.report.reclaimableBytes))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text(
                        "\(model.report.totalAssets) items · \(ByteCountFormat.string(for: model.report.totalBytes)) in library"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if model.isScanning, let progress = model.scanProgress {
                        ProgressView(value: progress.fraction) {
                            Text(progress.phase)
                        } currentValueLabel: {
                            Text("\(progress.processedCount)/\(progress.totalCount)")
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }

            if let cleaned = model.lastCleanupCount {
                Section {
                    Label(
                        "Moved \(cleaned) items to Recently Deleted",
                        systemImage: "trash.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            }

            if !model.report.recommendations.isEmpty {
                Section("Recommendations") {
                    ForEach(model.report.recommendations) { rec in
                        NavigationLink {
                            BucketDetailView(
                                summary: PhotosBucketSummary(
                                    bucket: rec.bucket,
                                    assetIDs: rec.assetIDs,
                                    reclaimableBytes: rec.estimatedSavings
                                )
                            )
                        } label: {
                            RecommendationRow(recommendation: rec)
                        }
                    }
                }
            }

            if !model.report.buckets.isEmpty {
                Section("Buckets") {
                    ForEach(model.report.buckets) { bucket in
                        NavigationLink {
                            BucketDetailView(summary: bucket)
                        } label: {
                            BucketRow(summary: bucket)
                        }
                    }
                }
            } else if !model.isScanning && model.report.totalAssets > 0 {
                Section {
                    Text("No obvious cleanup candidates. Your library looks tidy.")
                        .foregroundStyle(.secondary)
                }
            } else if !model.isScanning && model.report.totalAssets == 0 {
                Section {
                    Button("Scan Photo Library") {
                        Task { await model.scan() }
                    }
                }
            }
        }
        .overlay {
            if model.isScanning && model.report.totalAssets == 0 {
                ProgressView("Scanning…")
            }
        }
        .task {
            if model.report.totalAssets == 0 && !model.isScanning {
                await model.scan()
            }
        }
    }
}

struct RecommendationRow: View {
    let recommendation: PhotosRecommendation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: recommendation.bucket.systemImage)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.body.weight(.medium))
                Text(recommendation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(ByteCountFormat.string(for: recommendation.estimatedSavings))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

struct BucketRow: View {
    let summary: PhotosBucketSummary

    var body: some View {
        HStack {
            Label(summary.bucket.title, systemImage: summary.bucket.systemImage)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(summary.itemCount)")
                    .font(.body.weight(.medium))
                Text(ByteCountFormat.string(for: summary.reclaimableBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BucketDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    let summary: PhotosBucketSummary
    @State private var preview: AssetPreviewRequest?
    @State private var hiddenIDs: Set<String> = []
    @State private var pendingDeleteIDs: [String] = []
    @State private var confirmDelete = false

    private var duplicateGroups: [PhotosDuplicateGroup] {
        model.duplicateGroups(for: summary)
    }

    private var usesGroupedDuplicates: Bool {
        summary.bucket == .exactDuplicates || summary.bucket == .similar
    }

    private var isScreenshots: Bool {
        summary.bucket == .screenshots
    }

    private var visibleItemIDs: [String] {
        let remaining = summary.assetIDs.filter { !hiddenIDs.contains($0) }
        if isScreenshots {
            return model.rankedScreenshotIDs(remaining)
        }
        return remaining
    }

    var body: some View {
        List {
            Section {
                Text(summary.bucket.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(visibleItemIDs.count) items · \(ByteCountFormat.string(for: summary.reclaimableBytes)) reclaimable")
                    .font(.footnote)
                if usesGroupedDuplicates {
                    Text("Grouped so you can keep the best copy in each set. Tap a thumbnail to view or play.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isScreenshots {
                    Text("Swipe left to delete one item, or open the preview and tap Delete. Labels and keep scores are on-device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if usesGroupedDuplicates {
                ForEach(Array(duplicateGroups.enumerated()), id: \.element.id) { index, group in
                    let visibleAssets = group.assets.filter { !hiddenIDs.contains($0.id) }
                    if !visibleAssets.isEmpty {
                        Section {
                            ForEach(visibleAssets) { asset in
                                assetRow(
                                    asset: asset,
                                    assetID: asset.id,
                                    keepLabel: !model.selectedIDs.contains(asset.id)
                                        ? (asset.id == group.suggestedKeepID ? "Keeping · suggested" : "Keeping")
                                        : nil,
                                    onKeepOnly: { model.keepOnly(asset.id, in: group) }
                                )
                            }
                        } header: {
                            Text(groupHeader(index: index, group: group))
                        }
                    }
                }
            } else {
                Section("Items") {
                    ForEach(visibleItemIDs, id: \.self) { id in
                        let asset = model.assetsByID[id]
                        assetRow(asset: asset, assetID: id, keepLabel: nil, onKeepOnly: nil)
                    }
                }
            }
        }
        .navigationTitle(summary.bucket.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select All") {
                    model.selectAll(for: summary)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                NavigationLink {
                    ReviewCleanupView()
                } label: {
                    Text(cleanupButtonTitle)
                }
                .disabled(model.selectedIDs.isEmpty)
            }
        }
        .onAppear {
            if model.selectedIDs.isEmpty {
                model.selectDefault(for: summary)
            }
            if isScreenshots {
                model.seedScreenshotInsights()
            }
        }
        .task(id: isScreenshots ? visibleItemIDs.prefix(24).joined(separator: ",") : "") {
            guard isScreenshots else { return }
            await model.refineScreenshotInsights(for: Array(visibleItemIDs.prefix(24)))
        }
        .fullScreenCover(item: $preview) { request in
            MediaPreviewView(
                assetID: request.id,
                isVideo: request.isVideo,
                title: request.title,
                subtitle: request.subtitle,
                onDelete: {
                    let ok = await model.moveToRecentlyDeleted(ids: [request.id], rescan: false)
                    if ok {
                        hiddenIDs.insert(request.id)
                    }
                    return ok
                }
            )
        }
        .confirmationDialog(
            pendingDeleteIDs.count == 1
                ? "Move this item to Recently Deleted?"
                : "Move \(pendingDeleteIDs.count) items to Recently Deleted?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                let ids = pendingDeleteIDs
                pendingDeleteIDs = []
                Task {
                    let ok = await model.moveToRecentlyDeleted(ids: ids, rescan: false)
                    if ok {
                        hiddenIDs.formUnion(ids)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteIDs = []
            }
        } message: {
            Text("You can recover it in Photos for about 30 days.")
        }
    }

    private func assetRow(
        asset: PhotoAssetRecord?,
        assetID: String,
        keepLabel: String?,
        onKeepOnly: (() -> Void)?
    ) -> some View {
        let insight = isScreenshots ? model.screenshotInsights[assetID] : nil
        return AssetCleanupRow(
            asset: asset,
            assetID: assetID,
            isSelected: model.selectedIDs.contains(assetID),
            keepLabel: keepLabel,
            insight: insight,
            onToggle: { model.toggleSelection(assetID) },
            onKeepOnly: onKeepOnly,
            onPreview: {
                preview = AssetPreviewRequest(
                    id: assetID,
                    isVideo: asset?.isVideo == true,
                    title: insight?.label ?? assetTitle(asset),
                    subtitle: insight?.reason
                )
            },
            onDelete: {
                pendingDeleteIDs = [assetID]
                confirmDelete = true
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                pendingDeleteIDs = [assetID]
                confirmDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var cleanupButtonTitle: String {
        let n = model.selectedIDs.count
        if n == 0 { return "Select items" }
        return "Review \(n) · \(ByteCountFormat.string(for: model.selectedReclaimableBytes))"
    }

    private func groupHeader(index: Int, group: PhotosDuplicateGroup) -> String {
        let reclaim = ByteCountFormat.string(for: group.reclaimableSize)
        return "Group \(index + 1) · \(group.assets.count) items · \(reclaim) reclaimable"
    }
}

private struct AssetPreviewRequest: Identifiable {
    let id: String
    let isVideo: Bool
    let title: String
    var subtitle: String?
}

private struct AssetCleanupRow: View {
    let asset: PhotoAssetRecord?
    var assetID: String?
    let isSelected: Bool
    let keepLabel: String?
    var insight: PhotosScreenshotInsight?
    let onToggle: () -> Void
    let onKeepOnly: (() -> Void)?
    let onPreview: () -> Void
    var onDelete: (() -> Void)?

    private var resolvedID: String {
        asset?.id ?? assetID ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Selected for cleanup" : "Not selected")

            Button(action: onPreview) {
                PhotoThumbnailView(assetID: resolvedID, isVideo: asset?.isVideo == true, side: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(asset?.isVideo == true ? "Play video" : "View photo")

            VStack(alignment: .leading, spacing: 4) {
                Text(insight?.label ?? assetTitle(asset))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(insight?.reason ?? assetSubtitle(asset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let insight {
                        Text(insight.action.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(scoreColor(insight.action))
                    }
                    if let keepLabel {
                        Text(keepLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    if let onKeepOnly, isSelected {
                        Button("Keep this") {
                            onKeepOnly()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                    Button(asset?.isVideo == true ? "Play" : "View") {
                        onPreview()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    if let onDelete {
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let insight {
                    Text("\(insight.keepScore)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(scoreColor(insight.action))
                }
                if let asset {
                    Text(ByteCountFormat.string(for: asset.byteSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ action: PhotosScreenshotKeepAction) -> Color {
        switch action {
        case .trash: return .orange
        case .review: return .blue
        case .keep: return .green
        }
    }
}

private func assetTitle(_ asset: PhotoAssetRecord?) -> String {
    guard let asset else { return "Unknown item" }
    if asset.isScreenshot { return "Screenshot" }
    if asset.isVideo { return "Video" }
    if asset.isBurst { return "Burst photo" }
    return "Photo"
}

private func assetSubtitle(_ asset: PhotoAssetRecord?) -> String {
    guard let asset else { return "" }
    var parts: [String] = []
    if let date = asset.creationDate {
        parts.append(date.formatted(date: .abbreviated, time: .omitted))
    }
    if asset.isVideo, asset.durationSeconds > 0 {
        parts.append(durationLabel(asset.durationSeconds))
    } else if asset.pixelWidth > 0 {
        parts.append("\(asset.pixelWidth)×\(asset.pixelHeight)")
    }
    if asset.isFavorite {
        parts.append("Favorite")
    }
    return parts.joined(separator: " · ")
}

private func durationLabel(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let secs = total % 60
    return String(format: "%d:%02d", minutes, secs)
}

struct ReviewCleanupView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPresented = false

    var body: some View {
        List {
            Section {
                Text(
                    "Selected items will move to Recently Deleted in Photos. You can recover them there for about 30 days. DiskWise never permanently empties Recently Deleted."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Summary") {
                LabeledContent("Items", value: "\(model.selectedIDs.count)")
                LabeledContent(
                    "Space to free",
                    value: ByteCountFormat.string(for: model.selectedReclaimableBytes)
                )
            }

            Section {
                Button(role: .destructive) {
                    confirmPresented = true
                } label: {
                    if model.isCleaning {
                        ProgressView()
                    } else {
                        Text("Move to Recently Deleted")
                    }
                }
                .disabled(model.selectedIDs.isEmpty || model.isCleaning)
            }
        }
        .navigationTitle("Confirm cleanup")
        .confirmationDialog(
            "Move \(model.selectedIDs.count) items to Recently Deleted?",
            isPresented: $confirmPresented,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                Task {
                    await model.moveSelectedToRecentlyDeleted()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
