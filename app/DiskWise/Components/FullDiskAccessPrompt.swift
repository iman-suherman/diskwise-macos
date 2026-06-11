import AppKit
import DiskScannerKit
import SwiftUI

enum FullDiskAccessWizardStep: Equatable {
    case needsPermission
    case waiting
    case granted
}

enum FullDiskAccessSettings {
    static func open() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]

        for link in urls {
            if let url = URL(string: link), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static var appBundlePath: String {
        FullDiskAccess.appBundlePath
    }
}

struct FullDiskAccessGateOverlay: View {
    let step: FullDiskAccessWizardStep
    let mountedVolumeCount: Int
    let missingVolumePaths: [String]
    let onGrantAccess: () -> Void
    let onDismiss: () -> Void
    let onCancelWaiting: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            FullDiskAccessPromptView(
                step: step,
                mountedVolumeCount: mountedVolumeCount,
                missingVolumePaths: missingVolumePaths,
                onGrantAccess: onGrantAccess,
                onDismiss: onDismiss,
                onCancelWaiting: onCancelWaiting
            )
            .padding(28)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(32)
        }
        .transition(.opacity)
        .zIndex(100)
    }
}

struct FullDiskAccessPromptView: View {
    let step: FullDiskAccessWizardStep
    let mountedVolumeCount: Int
    let missingVolumePaths: [String]
    let onGrantAccess: () -> Void
    let onDismiss: () -> Void
    let onCancelWaiting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            GroupBox {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }

            if !missingVolumePaths.isEmpty, step == .needsPermission {
                GroupBox("Connected but not visible") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(missingVolumePaths, id: \.self) { path in
                            Label(path, systemImage: "externaldrive.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            footer
        }
        .padding(28)
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbol)
                .font(.system(size: 34))
                .foregroundStyle(headerColor)
                .symbolEffect(.pulse, isActive: step == .waiting)

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.title2.bold())
                Text(headerSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .needsPermission:
            VStack(alignment: .leading, spacing: 12) {
                Text("To scan all disks, DiskWise requires Full Disk Access.")
                Text("DiskWise may not appear in the list until you add it manually.")
                    .foregroundStyle(.secondary)
                Text("System Settings → Privacy & Security → Full Disk Access")
                    .font(.body.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                manualAddSteps
            }

        case .waiting:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Waiting for permission…")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(number: 1, text: "Click + in Full Disk Access")
                    instructionRow(number: 2, text: "Choose Reveal in Finder below, then select DiskWise.app")
                    instructionRow(number: 3, text: "Enable the toggle next to DiskWise")
                    instructionRow(number: 4, text: "Return here — scanning starts automatically")
                }
                .foregroundStyle(.secondary)

                manualAddSteps
            }

        case .granted:
            VStack(alignment: .leading, spacing: 12) {
                Label("DiskWise detected access", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning drives…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .needsPermission:
            VStack(spacing: 10) {
                HStack {
                    Button("Grant Permission", action: onGrantAccess)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)

                    Button("Reveal in Finder") {
                        FullDiskAccessSettings.revealAppInFinder()
                    }

                    Spacer()

                    Button("Not Now", action: onDismiss)
                }
            }

        case .waiting:
            HStack {
                Button("Open Settings Again") {
                    FullDiskAccessSettings.open()
                }

                Button("Reveal in Finder") {
                    FullDiskAccessSettings.revealAppInFinder()
                }

                Spacer()

                Button("Not Now", action: onCancelWaiting)
            }

        case .granted:
            EmptyView()
        }
    }

    private var manualAddSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("If DiskWise is missing from the list:")
                .font(.subheadline.weight(.semibold))
            Text(FullDiskAccessSettings.appBundlePath)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.caption.monospaced())
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.subheadline)
        }
    }

    private var headerSymbol: String {
        switch step {
        case .needsPermission: "lock.shield"
        case .waiting: "gear.badge.questionmark"
        case .granted: "checkmark.shield"
        }
    }

    private var headerColor: Color {
        switch step {
        case .needsPermission: .orange
        case .waiting: .blue
        case .granted: .green
        }
    }

    private var headerTitle: String {
        switch step {
        case .needsPermission: "DiskWise needs permission"
        case .waiting: "Enable Full Disk Access"
        case .granted: "Permission granted"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .needsPermission:
            if mountedVolumeCount == 0 {
                return "No drives were detected on first launch."
            }
            if !missingVolumePaths.isEmpty {
                return "Some connected external drives are not visible yet."
            }
            return "Grant access to scan internal and external drives."
        case .waiting:
            return "DiskWise will detect the change and start scanning."
        case .granted:
            return "Full Disk Access is enabled."
        }
    }
}

struct FullDiskAccessBanner: View {
    let missingVolumePaths: [String]
    let onGrantAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access required", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Grant access to scan all connected drives. DiskWise detects the change automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !missingVolumePaths.isEmpty {
                Text(missingVolumePaths.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button("Grant Access", action: onGrantAccess)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
