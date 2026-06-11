import SwiftUI
import Charts
import AppKit
import DatabaseKit

struct StorageCategoryBarChart: View {
    let items: [(name: String, totalSize: Int64, fileCount: Int)]
    let totalSize: Int64
    let selectedName: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items, id: \.name) { item in
                CategoryBarRow(
                    name: item.name,
                    totalSize: item.totalSize,
                    fileCount: item.fileCount,
                    fraction: fraction(for: item.totalSize),
                    color: CategoryPalette.color(for: item.name),
                    icon: CategoryPalette.icon(for: item.name),
                    isSelected: selectedName == item.name,
                    onTap: { onSelect(item.name) }
                )
            }
        }
    }

    private func fraction(for size: Int64) -> Double {
        guard totalSize > 0 else { return 0 }
        return Double(size) / Double(totalSize)
    }
}

struct CategoryBarRow: View {
    let name: String
    let totalSize: Int64
    let fileCount: Int
    let fraction: Double
    let color: Color
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 18)

                    Text(name)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(DiskWiseFormatters.bytes.string(fromByteCount: totalSize))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 72, alignment: .trailing)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(6, geometry.size.width * fraction))
                    }
                }
                .frame(height: 10)

                Text("\(fileCount.formatted()) files · tap for details")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? color.opacity(0.14) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? color.opacity(0.45) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct StorageCategoryDetailPanel: View {
    let groupName: String
    let subSummaries: [CategorySummary]
    let files: [FileRecord]
    let totalSize: Int64
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Label("All types", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(groupName)
                    .font(.headline)
            }

            if subSummaries.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Breakdown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Chart(subSummaries, id: \.category) { summary in
                        BarMark(
                            x: .value("Size", summary.totalSize),
                            y: .value("Type", summary.category.granularName)
                        )
                        .foregroundStyle(CategoryPalette.color(for: summary.category.chartGroup).gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(preset: .aligned, position: .bottom)
                    }
                    .frame(height: CGFloat(subSummaries.count * 36 + 24))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Largest files")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if files.isEmpty {
                    Text("No files indexed for this category yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(files.prefix(12), id: \.path) { file in
                        CategoryFileRow(file: file, groupTotal: totalSize)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct CategoryFileRow: View {
    let file: FileRecord
    let groupTotal: Int64

    private var fraction: Double {
        guard groupTotal > 0 else { return 0 }
        return Double(file.size) / Double(groupTotal)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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

            VStack(alignment: .trailing, spacing: 4) {
                Text(DiskWiseFormatters.bytes.string(fromByteCount: file.size))
                    .font(.subheadline.weight(.semibold))

                Text("\(Int(fraction * 100))% of type")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum CategoryPalette {
    static func color(for name: String) -> Color {
        switch name {
        case "Media": return .purple
        case "Documents": return .blue
        case "Applications": return .indigo
        case "Development": return .teal
        case "Downloads": return .cyan
        case "Caches": return .orange
        case "Archives": return .brown
        case "Backups": return .mint
        case "Containers": return .pink
        case "Virtual Machines": return .red
        case "Temporary": return .yellow
        default: return .gray
        }
    }

    static func icon(for name: String) -> String {
        switch name {
        case "Media": return "photo.on.rectangle.angled"
        case "Documents": return "doc.text"
        case "Applications": return "app"
        case "Development": return "chevron.left.forwardslash.chevron.right"
        case "Downloads": return "arrow.down.circle"
        case "Caches": return "memorychip"
        case "Archives": return "archivebox"
        case "Backups": return "externaldrive.badge.timemachine"
        case "Containers": return "shippingbox"
        case "Virtual Machines": return "desktopcomputer"
        case "Temporary": return "clock.badge.exclamationmark"
        default: return "folder"
        }
    }
}
