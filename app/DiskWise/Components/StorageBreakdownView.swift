import SwiftUI
import Charts
import AppKit
import DatabaseKit
import DiskScannerKit

enum PieChartHitTester {
    static func category(
        at location: CGPoint,
        in size: CGSize,
        items: [(name: String, totalSize: Int64, fileCount: Int)],
        totalSize: Int64
    ) -> String? {
        guard totalSize > 0, !items.isEmpty else { return nil }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let innerRadius = radius * 0.58

        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= radius else { return nil }

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let pointer = angle / (2 * .pi)

        var cumulative = 0.0
        for item in items {
            cumulative += Double(item.totalSize) / Double(totalSize)
            if pointer <= cumulative {
                return item.name
            }
        }
        return items.last?.name
    }
}

struct StorageTypePieChart: View {
    let items: [(name: String, totalSize: Int64, fileCount: Int)]
    let totalSize: Int64
    let selectedName: String?
    let hoveredName: String?
    let onSelect: (String) -> Void
    let onHover: (String?) -> Void
    let onShowInFinder: (String) -> Void
    let onDelete: (String) -> Void

    @State private var angleSelection: String?

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width

            ZStack {
                Chart(items, id: \.name) { item in
                    SectorMark(
                        angle: .value("Size", item.totalSize),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Type", item.name))
                    .opacity(segmentOpacity(for: item.name))
                }
                .chartForegroundStyleScale(
                    domain: items.map(\.name),
                    range: items.map { CategoryPalette.color(for: $0.name) }
                )
                .chartAngleSelection(value: $angleSelection)
                .chartLegend(.hidden)
                .frame(width: side, height: side)

                centerLabel
                    .frame(width: side * 0.44)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                if let name = contextMenuCategory {
                    Button {
                        onShowInFinder(name)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        onDelete(name)
                    } label: {
                        Label("Move to Trash…", systemImage: "trash")
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onHover(
                        PieChartHitTester.category(
                            at: location,
                            in: CGSize(width: side, height: side),
                            items: items,
                            totalSize: totalSize
                        )
                    )
                case .ended:
                    onHover(nil)
                }
            }
            .onTapGesture { location in
                if let name = PieChartHitTester.category(
                    at: location,
                    in: CGSize(width: side, height: side),
                    items: items,
                    totalSize: totalSize
                ) {
                    onSelect(name)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.2), value: hoveredName)
        .animation(.easeInOut(duration: 0.2), value: selectedName)
        .onChange(of: angleSelection) { _, newValue in
            guard let newValue else { return }
            onSelect(newValue)
            angleSelection = nil
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        VStack(spacing: 4) {
            if let displayName = hoveredName ?? selectedName,
               let item = items.first(where: { $0.name == displayName }) {
                Image(systemName: CategoryPalette.icon(for: displayName))
                    .font(.title3)
                    .foregroundStyle(CategoryPalette.color(for: displayName))
                Text(displayName)
                    .font(.headline)
                Text("\(Int(fraction(for: item.totalSize) * 100))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(DiskWiseFormatters.bytes.string(fromByteCount: item.totalSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DiskWiseFormatters.bytes.string(fromByteCount: totalSize))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(items.count) types")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var contextMenuCategory: String? {
        hoveredName ?? angleSelection ?? selectedName
    }

    private func fraction(for size: Int64) -> Double {
        guard totalSize > 0 else { return 0 }
        return Double(size) / Double(totalSize)
    }

    private func segmentOpacity(for name: String) -> Double {
        let highlighted = hoveredName ?? selectedName
        guard let highlighted else { return 1 }
        return highlighted == name ? 1 : 0.22
    }
}

struct UnmappedStorageBanner: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let volume: MountedVolume
    let overview: StorageOverview

    var body: some View {
        let unaccounted = viewModel.unaccountedStorageBytes(volume: volume, overview: overview)
        let fraction = volume.usedSize > 0 ? Double(unaccounted) / Double(volume.usedSize) : 0

        if unaccounted > 1_073_741_824, fraction > 0.05 {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("\(DiskWiseFormatters.bytes.string(fromByteCount: unaccounted)) of used space is not fully mapped")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "questionmark.folder.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(viewModel.unaccountedStorageDetail(volume: volume, overview: overview))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("DiskWise compares volume used space with the indexed total. Unmapped space is often in protected system folders, app containers, or APFS snapshots — not missing files from your scan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to map more of it")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Label("Grant Full Disk Access so DiskWise can read protected folders.", systemImage: "1.circle")
                        Label("Rescan this drive after access is granted.", systemImage: "2.circle")
                        if viewModel.appSettings.scanMode == .fast {
                            Label("Switch to Deep scan in Settings for broader indexing.", systemImage: "3.circle")
                        } else {
                            Label("Some space may remain unmapped even after a Deep scan (snapshots, purgeable cache).", systemImage: "3.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        if !viewModel.hasFullDiskAccess {
                            Button {
                                viewModel.presentFullDiskAccessOverlay()
                            } label: {
                                Label("Grant Full Disk Access", systemImage: "lock.open")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            viewModel.scan(volume: volume)
                        } label: {
                            Label("Rescan \(volume.name)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)

                        if viewModel.appSettings.scanMode == .fast {
                            Button("Use Deep Scan") {
                                viewModel.appSettings.scanMode = .deep
                                viewModel.scan(volume: volume)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct StorageCategoryBarChart: View {
    let items: [(name: String, totalSize: Int64, fileCount: Int)]
    let totalSize: Int64
    let selectedName: String?
    let hoveredName: String?
    let onSelect: (String) -> Void
    let onHover: (String?) -> Void
    var onShowInFinder: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var columns: Int = 2

    var body: some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, columns))

        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(items, id: \.name) { item in
                CategoryBarRow(
                    name: item.name,
                    totalSize: item.totalSize,
                    fileCount: item.fileCount,
                    fraction: fraction(for: item.totalSize),
                    color: CategoryPalette.color(for: item.name),
                    icon: CategoryPalette.icon(for: item.name),
                    isSelected: selectedName == item.name,
                    isHovered: hoveredName == item.name,
                    onTap: { onSelect(item.name) },
                    onHover: { hovering in
                        onHover(hovering ? item.name : nil)
                    },
                    onShowInFinder: onShowInFinder.map { handler in { handler(item.name) } },
                    onDelete: onDelete.map { handler in { handler(item.name) } }
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
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    var onShowInFinder: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 18)

                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(DiskWiseFormatters.bytes.string(fromByteCount: totalSize))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    .fill(rowBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(rowBorder, lineWidth: isSelected || isHovered ? 1.5 : 0)
            }
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .contextMenu {
            if let onShowInFinder {
                Button {
                    onShowInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
            }
        }
    }

    private var rowBackground: Color {
        if isSelected || isHovered {
            return color.opacity(0.14)
        }
        return Color.primary.opacity(0.04)
    }

    private var rowBorder: Color {
        if isSelected || isHovered {
            return color.opacity(0.45)
        }
        return .clear
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

struct StorageResultsChartsSection: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let volume: MountedVolume?
    let overview: StorageOverview

    var body: some View {
        let grouped = viewModel.groupedCategorySummaries(from: overview.categorySummaries)

        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Storage by Type") {
                if grouped.isEmpty {
                    Text("No category data yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    StorageTypePieChart(
                        items: grouped,
                        totalSize: overview.totalSize,
                        selectedName: viewModel.selectedStorageCategory,
                        hoveredName: viewModel.hoveredStorageCategory,
                        onSelect: { viewModel.selectStorageCategory($0) },
                        onHover: { viewModel.hoveredStorageCategory = $0 },
                        onShowInFinder: { viewModel.revealStorageCategoryInFinder($0) },
                        onDelete: { viewModel.prepareCategoryCleanup($0) }
                    )
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)

            if let volume {
                UnmappedStorageBanner(volume: volume, overview: overview)
            }

            GroupBox("Storage Breakdown") {
                if grouped.isEmpty {
                    Text("No category data yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else if let selected = viewModel.selectedStorageCategory {
                    StorageCategoryDetailPanel(
                        groupName: selected,
                        subSummaries: viewModel.subSummaries(forChartGroup: selected),
                        files: viewModel.categoryDetailFiles,
                        totalSize: grouped.first(where: { $0.name == selected })?.totalSize ?? overview.totalSize,
                        onBack: { viewModel.clearStorageCategorySelection() }
                    )
                } else {
                    StorageCategoryBarChart(
                        items: grouped,
                        totalSize: overview.totalSize,
                        selectedName: viewModel.selectedStorageCategory,
                        hoveredName: viewModel.hoveredStorageCategory,
                        onSelect: { viewModel.selectStorageCategory($0) },
                        onHover: { viewModel.hoveredStorageCategory = $0 },
                        onShowInFinder: { viewModel.revealStorageCategoryInFinder($0) },
                        onDelete: { viewModel.prepareCategoryCleanup($0) },
                        columns: 2
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
