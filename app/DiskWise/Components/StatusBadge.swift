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
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    isAnimating ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isAnimating
                )

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

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
        .padding(.vertical, 8)
        .background(kind.tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(kind.tint.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct DeviceSidebarRow: View {
    let volume: MountedVolume
    let isSelected: Bool
    let isIndexed: Bool
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
                    .tint(usageColor(for: volume.usageFraction))

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
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            if let onEject {
                Button {
                    onEject()
                } label: {
                    Label("Eject \"\(volume.name)\"", systemImage: "eject.fill")
                }
            }
        }
    }

    private func usageColor(for fraction: Double) -> Color {
        switch fraction {
        case 0.9...: return .red
        case 0.75..<0.9: return .orange
        default: return .accentColor
        }
    }
}

// Backward-compatible alias
typealias DiskSidebarRow = DeviceSidebarRow
