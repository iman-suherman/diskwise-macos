import SwiftUI
import DiskScannerKit

struct StatusBadge: View {
    let message: String
    let kind: AppStatusKind
    var isAnimating: Bool = false
    var onRefresh: (() -> Void)? = nil

    private var showsRefresh: Bool {
        onRefresh != nil && kind == .error && !isAnimating
    }

    var body: some View {
        HStack(spacing: 8) {
            if isAnimating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.tint)
                    .frame(width: 16, height: 16)
            }

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if showsRefresh {
                Button {
                    onRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Retry scan")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(kind.tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(kind.tint.opacity(0.25), lineWidth: 1)
        }
        .frame(maxWidth: 360, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct DeviceSidebarRow: View {
    let volume: MountedVolume
    let isSelected: Bool
    let isIndexed: Bool
    var isScanDisabled: Bool = false
    var isEjectDisabled: Bool = false
    var onScan: (() -> Void)? = nil
    var onScanFolder: (() -> Void)? = nil
    var onEject: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(volume.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(DiskWiseFormatters.bytes.string(fromByteCount: volume.totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: volume.usageFraction)
                    .tint(MenuBarDiskThresholds.statusColor(for: volume))

                HStack(spacing: 6) {
                    Text("\(DiskWiseFormatters.bytes.string(fromByteCount: volume.freeSize)) free")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isIndexed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("Scanned")
                    }
                }
            }

            if isSelected, let onScan {
                Button {
                    onScan()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isScanDisabled ? .tertiary : .secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isScanDisabled)
                .help(
                    isScanDisabled
                        ? "Wait for scan to finish"
                        : (isIndexed ? "Rescan \"\(volume.name)\"" : "Scan \"\(volume.name)\"")
                )
            }

            if let onEject {
                Button {
                    onEject()
                } label: {
                    Image(systemName: "eject.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isEjectDisabled ? .tertiary : .secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isEjectDisabled)
                .help(isEjectDisabled ? "Wait for scan to finish" : "Eject \"\(volume.name)\"")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if let onScan {
                Button {
                    onScan()
                } label: {
                    Label(
                        isIndexed ? "Rescan \"\(volume.name)\"" : "Scan \"\(volume.name)\"",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(isScanDisabled)
            }

            if let onScanFolder {
                Button {
                    onScanFolder()
                } label: {
                    Label("Scan Folder…", systemImage: "folder.badge.plus")
                }
                .disabled(isScanDisabled)
            }

            if let onEject {
                Button {
                    onEject()
                } label: {
                    Label("Eject \"\(volume.name)\"", systemImage: "eject.fill")
                }
                .disabled(isEjectDisabled)
            }
        }
    }
}

// Backward-compatible alias
typealias DiskSidebarRow = DeviceSidebarRow
