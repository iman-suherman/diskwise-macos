import DiskScannerKit
import SwiftUI

struct ScanModePromptOverlay: View {
    let volumeName: String
    let onFastScan: () -> Void
    let onDeepScan: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Scan \(volumeName)")
                        .font(.title2.bold())
                    Text("Choose how DiskWise should index this drive for the first time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                VStack(alignment: .leading, spacing: 12) {
                    scanOptionCard(
                        title: "Fast Scan",
                        detail: ScanMode.fast.detail,
                        icon: "bolt.fill",
                        tint: .accentColor,
                        action: onFastScan,
                        isPrimary: true
                    )

                    scanOptionCard(
                        title: "Deep Scan",
                        detail: ScanMode.deep.detail,
                        icon: "scope",
                        tint: .orange,
                        action: onDeepScan,
                        isPrimary: false
                    )
                }
                .frame(maxWidth: 460)

                VolumeScanScheduleRecommendationSection(embeddedInScanPanel: true)
                    .frame(maxWidth: 460)

                Button("Not Now") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
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

    @ViewBuilder
    private func scanOptionCard(
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void,
        isPrimary: Bool
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(isPrimary ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(isPrimary ? 0.25 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct UnindexedVolumeScanPanel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let volume: MountedVolume

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text(volume.name)
                    .font(.title2.bold())
                Text("This drive has not been indexed yet. Fast scan is recommended for a first pass; choose Deep scan when you need every file mapped individually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        viewModel.startScan(with: .fast, volume: volume)
                    } label: {
                        Label("Fast Scan", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isVolumeBusy(volume))

                    Button {
                        viewModel.startScan(with: .deep, volume: volume)
                    } label: {
                        Label("Deep Scan", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(viewModel.isVolumeBusy(volume))

                    Button {
                        viewModel.scanFolder(on: volume)
                    } label: {
                        Label("Scan Folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isVolumeBusy(volume))
                }

                VolumeScanScheduleRecommendationSection(embeddedInScanPanel: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
