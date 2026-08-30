import PhotosKit
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !model.canScan {
                    PermissionView()
                } else {
                    DashboardView()
                }
            }
            .navigationTitle("DiskWise")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.canScan {
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
                Button("Allow Photos Access") {
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

    var body: some View {
        List {
            Section {
                Text(summary.bucket.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(summary.itemCount) items · \(ByteCountFormat.string(for: summary.reclaimableBytes)) reclaimable")
                    .font(.footnote)
            }

            Section("Items") {
                ForEach(summary.assetIDs, id: \.self) { id in
                    let asset = model.assetsByID[id]
                    Button {
                        model.toggleSelection(id)
                    } label: {
                        HStack {
                            Image(systemName: model.selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.selectedIDs.contains(id) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assetTitle(asset))
                                Text(assetSubtitle(asset))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let asset {
                                Text(ByteCountFormat.string(for: asset.byteSize))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(summary.bucket.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select All") {
                    model.selectDefault(for: summary)
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
        }
    }

    private var cleanupButtonTitle: String {
        let n = model.selectedIDs.count
        if n == 0 { return "Select items" }
        return "Review \(n) · \(ByteCountFormat.string(for: model.selectedReclaimableBytes))"
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
        if asset.pixelWidth > 0 {
            parts.append("\(asset.pixelWidth)×\(asset.pixelHeight)")
        }
        if asset.isFavorite {
            parts.append("Favorite")
        }
        return parts.joined(separator: " · ")
    }
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
