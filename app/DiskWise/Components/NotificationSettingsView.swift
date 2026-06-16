import SwiftUI
import DiskScannerKit

struct NotificationSettingsForm: View {
    @ObservedObject var settings: AppSettings
    let volumes: [MountedVolume]

    private var notifiableVolumes: [MountedVolume] {
        volumes.filter { $0.totalSize >= DiskSpaceAlertLevel.minimumNotifiableTotalBytes }
    }

    var body: some View {
        Form {
            diskSpaceSection
            memorySection
            memoryAnalyzerSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var diskSpaceSection: some View {
        Section {
            Toggle("Alert when disk space is low", isOn: $settings.diskSpaceNotificationsEnabled)

            Text("Choose a default threshold for all drives, then customize each storage volume in Disk Analysis → Notifications or below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("Default disk threshold") {
            thresholdModePicker(
                selection: $settings.diskNotificationThresholdMode,
                description: settings.diskNotificationThresholdMode.diskDescription
            )

            if settings.diskNotificationThresholdMode == .percentage {
                percentThresholdRow(
                    title: "Free space remaining",
                    value: $settings.diskNotificationFreePercent,
                    range: NotificationThresholdDefaults.diskFreePercentRange,
                    suffix: "%"
                )
            } else {
                gigabyteThresholdRow(
                    title: "Free space remaining",
                    value: $settings.diskNotificationFreeGigabytes,
                    range: NotificationThresholdDefaults.diskFreeGigabytesRange,
                    step: 5
                )
            }
        }

        Section("Per-drive thresholds") {
            if notifiableVolumes.isEmpty {
                Text("No drives detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notifiableVolumes) { volume in
                    DiskVolumeNotificationSettingsRow(
                        settings: settings,
                        volume: volume
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var memorySection: some View {
        Section {
            Toggle("Alert when memory usage is high", isOn: $settings.systemHealthNotificationsEnabled)

            Text("This Mac has \(formattedMemoryTotal) of RAM. Choose a percentage or free-memory amount threshold.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("Memory threshold") {
            thresholdModePicker(
                selection: $settings.memoryNotificationThresholdMode,
                description: settings.memoryNotificationThresholdMode.memoryDescription
            )

            if settings.memoryNotificationThresholdMode == .percentage {
                percentThresholdRow(
                    title: "Memory used",
                    value: $settings.memoryNotificationUsedPercent,
                    range: NotificationThresholdDefaults.memoryUsedPercentRange,
                    suffix: "%"
                )
            } else {
                gigabyteThresholdRow(
                    title: "Free memory remaining",
                    value: $settings.memoryNotificationFreeGigabytes,
                    range: NotificationThresholdDefaults.memoryFreeGigabytesRange,
                    step: 0.5
                )
            }
        }
    }

    private var memoryAnalyzerSection: some View {
        Section("Memory Analyzer") {
            Toggle("Monitor memory in the background", isOn: $settings.memoryAnalyzerEnabled)

            Toggle(
                "Notify when new insights are available",
                isOn: $settings.memoryAnalyzerNotificationsEnabled
            )
            .disabled(!settings.memoryAnalyzerEnabled)

            Text("Separate from usage alerts above — these notifications fire when DiskWise finds a new actionable memory recommendation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formattedMemoryTotal: String {
        String(format: "%.0f GB", NotificationThresholdDefaults.physicalMemoryGigabytes.rounded())
    }

    @ViewBuilder
    private func thresholdModePicker(
        selection: Binding<NotificationThresholdMode>,
        description: String
    ) -> some View {
        Picker("Threshold type", selection: selection) {
            ForEach(NotificationThresholdMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }

        Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func percentThresholdRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)\(suffix)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func gigabyteThresholdRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f GB", value.wrappedValue))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: value,
                in: range,
                step: step
            )
        }
        .padding(.vertical, 4)
    }
}

private struct DiskVolumeNotificationSettingsRow: View {
    @ObservedObject var settings: AppSettings
    let volume: MountedVolume

    private var volumeSummary: String {
        let freePercent = Int((max(0, 1 - volume.usageFraction) * 100).rounded())
        return "\(MenuBarFormatters.gigabytes(volume.freeSize)) free · \(freePercent)% remaining · \(MenuBarFormatters.gigabytes(volume.totalSize)) total"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.body.weight(.medium))
                Text(volumeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DiskVolumeNotificationSettingsEditor(settings: settings, volume: volume)
        }
        .padding(.vertical, 4)
    }
}

struct DiskVolumeNotificationSettingsEditor: View {
    @ObservedObject var settings: AppSettings
    let volume: MountedVolume

    @State private var override: DiskNotificationVolumeOverride

    init(settings: AppSettings, volume: MountedVolume) {
        self.settings = settings
        self.volume = volume
        _override = State(initialValue: settings.diskNotificationOverride(for: volume.mountPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Notify for this drive", isOn: enabledBinding)

            if override.isEnabled {
                Toggle("Use custom threshold", isOn: customThresholdBinding)

                if override.usesCustomThreshold {
                    Picker("Threshold type", selection: modeBinding) {
                        ForEach(NotificationThresholdMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if override.thresholdMode == .percentage {
                        percentRow
                    } else {
                        gigabyteRow
                    }
                } else {
                    Text(globalDefaultSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: settings.diskNotificationVolumeOverrides[volume.mountPath]) { _, newValue in
            if let newValue, newValue != override {
                override = newValue
            }
        }
    }

    private var globalDefaultSummary: String {
        let mode = settings.diskNotificationThresholdMode
        switch mode {
        case .percentage:
            return "Using global default: alert when free space drops below \(settings.diskNotificationFreePercent)%."
        case .absolute:
            return String(
                format: "Using global default: alert when free space drops below %.1f GB.",
                settings.diskNotificationFreeGigabytes
            )
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { override.isEnabled },
            set: { newValue in
                override.isEnabled = newValue
                persistOverride()
            }
        )
    }

    private var customThresholdBinding: Binding<Bool> {
        Binding(
            get: { override.usesCustomThreshold },
            set: { newValue in
                override.usesCustomThreshold = newValue
                persistOverride()
            }
        )
    }

    private var modeBinding: Binding<NotificationThresholdMode> {
        Binding(
            get: { override.thresholdMode },
            set: { newValue in
                override.thresholdMode = newValue
                persistOverride()
            }
        )
    }

    private var percentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Free space remaining")
                Spacer()
                Text("\(override.freePercent)%")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(override.freePercent) },
                    set: { newValue in
                        override.freePercent = Int(newValue.rounded())
                        persistOverride()
                    }
                ),
                in: Double(NotificationThresholdDefaults.diskFreePercentRange.lowerBound)...Double(NotificationThresholdDefaults.diskFreePercentRange.upperBound),
                step: 1
            )
        }
    }

    private var gigabyteRow: some View {
        let range = NotificationThresholdDefaults.diskFreeGigabytesRange(for: volume.totalSize)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Free space remaining")
                Spacer()
                Text(String(format: "%.1f GB", override.freeGigabytes))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { override.freeGigabytes },
                    set: { newValue in
                        override.freeGigabytes = newValue
                        persistOverride()
                    }
                ),
                in: range,
                step: 5
            )
        }
    }

    private func persistOverride() {
        settings.setDiskNotificationOverride(for: volume.mountPath, override: override)
    }
}

struct VolumeNotificationsTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var settings: AppSettings { viewModel.appSettings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.selectedVolume == nil {
                    ContentUnavailableView {
                        Label("Select a drive", systemImage: "internaldrive")
                    } description: {
                        Text("Choose a drive to configure low-space notifications for that volume.")
                    }
                    .padding(.vertical, 24)
                } else if let volume = viewModel.selectedVolume {
                    headerSection(volume: volume)

                    if !DiskSpaceAlertLevel.shouldNotify(for: volume) {
                        tooSmallVolumeNotice
                    } else {
                        globalNotificationsSection
                        driveNotificationsSection(volume: volume)
                        currentStatusSection(volume: volume)
                    }
                }
            }
            .padding(28)
        }
        .onAppear {
            SystemVolumeMonitor.shared.refresh()
        }
    }

    private func headerSection(volume: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.title2.bold())
            Text("\(volume.name) — customize low-space alerts for this drive. Global notification settings remain in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(volume.mountPath)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private var tooSmallVolumeNotice: some View {
        GroupBox {
            Label {
                Text("This volume is too small for disk-space alerts.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var globalNotificationsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Global disk alerts", systemImage: "bell")
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: settings.diskSpaceNotificationsEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(settings.diskSpaceNotificationsEnabled ? .green : .secondary)
                    Text(settings.diskSpaceNotificationsEnabled
                         ? "Low-space notifications are enabled"
                         : "Low-space notifications are turned off")
                        .font(.subheadline)
                }

                if settings.diskSpaceNotificationsEnabled {
                    Text(globalThresholdSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Turn on disk notifications in Settings to receive alerts for any drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Open Settings…") {
                    viewModel.openSettingsPane()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var globalThresholdSummary: String {
        switch settings.diskNotificationThresholdMode {
        case .percentage:
            return "Default threshold for all drives: \(settings.diskNotificationFreePercent)% free space remaining."
        case .absolute:
            return String(
                format: "Default threshold for all drives: %.1f GB free space remaining.",
                settings.diskNotificationFreeGigabytes
            )
        }
    }

    private func driveNotificationsSection(volume: MountedVolume) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("This drive", systemImage: "internaldrive")
                    .font(.headline)

                volumeCapacitySummary(volume: volume)

                DiskVolumeNotificationSettingsEditor(settings: settings, volume: volume)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func volumeCapacitySummary(volume: MountedVolume) -> some View {
        let freePercent = Int((max(0, 1 - volume.usageFraction) * 100).rounded())
        return Text(
            "\(MenuBarFormatters.gigabytes(volume.freeSize)) free · \(freePercent)% remaining · \(MenuBarFormatters.gigabytes(volume.totalSize)) total"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func currentStatusSection(volume: MountedVolume) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Current status", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.headline)

                if let resolved = settings.resolvedDiskNotificationSettings(for: volume) {
                    Text(resolved.alertDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if NotificationThresholdLogic.isDiskLowOnSpace(
                        freeSize: volume.freeSize,
                        totalSize: volume.totalSize,
                        settings: resolved
                    ) {
                        Label("Below threshold — you would receive a notification", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Label("Above threshold — no alert right now", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Notifications are disabled for this drive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
