import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    var onOpenSettings: (() -> Void)?

    private var appVersion: String { AppSettings.currentAppVersion }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var updateFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "—"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Iman Suherman"
    }

    var body: some View {
        VStack(spacing: 0) {
            aboutHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    whatsNewSection
                    configurationSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Check for Updates…") {
                    SparkleUpdaterController.shared.checkForUpdates()
                }

                if let onOpenSettings {
                    Button("Open Settings") {
                        dismiss()
                        onOpenSettings()
                    }
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 680)
    }

    private var aboutHeader: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

            Text("DiskWise")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Intelligent macOS storage consultant")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private var whatsNewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What’s New in \(appVersion)", systemImage: "sparkles")
                .font(.headline)

            ForEach(WhatsNewContent.pages(for: appVersion)) { page in
                aboutFeatureSection(page)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Settings & Configuration", systemImage: "gearshape")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    configurationRow(
                        title: "Performance preset",
                        value: settings.activePreset?.title ?? "Custom",
                        detail: settings.activePreset?.detail
                            ?? "Duplicate limit \(settings.duplicateScanFileLimit.formatted()) · Analysis limit \(settings.analysisFileLimit.formatted())"
                    )
                    Divider().padding(.vertical, 10)

                    configurationRow(
                        title: "Duplicate detection (Step 2)",
                        value: "\(settings.duplicateScanFileLimit.formatted()) files",
                        detail: "Checks the largest files by size · range \(AppSettings.duplicateScanFileLimitRange.lowerBound.formatted())–\(AppSettings.duplicateScanFileLimitRange.upperBound.formatted())"
                    )
                    Divider().padding(.vertical, 10)

                    configurationRow(
                        title: "Storage analysis (Step 3)",
                        value: "\(settings.analysisFileLimit.formatted()) files",
                        detail: "Samples the largest files for recommendations · range \(AppSettings.analysisFileLimitRange.lowerBound.formatted())–\(AppSettings.analysisFileLimitRange.upperBound.formatted())"
                    )
                    Divider().padding(.vertical, 10)

                    configurationRow(
                        title: "Step 1 indexing",
                        value: "All files",
                        detail: "Every file on the selected volume is indexed before duplicate and analysis limits apply."
                    )
                    Divider().padding(.vertical, 10)

                    configurationRow(
                        title: "Automatic updates",
                        value: "On",
                        detail: "Checks daily and downloads updates in the background (Sparkle)."
                    )
                    Divider().padding(.vertical, 10)

                    configurationRow(
                        title: "Update feed",
                        value: updateFeedURL,
                        detail: nil,
                        monospacedValue: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Change scan limits and presets in Settings (⌘,).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func aboutFeatureSection(_ page: WhatsNewPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(page.title, systemImage: page.icon)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)

            if !page.message.isEmpty {
                Text(page.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !page.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(page.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(bullet)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func configurationRow(
        title: String,
        value: String,
        detail: String?,
        monospacedValue: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                Text(value)
                    .font(monospacedValue ? .caption.monospaced() : .subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(monospacedValue ? 3 : 1)
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
