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

            Text("Choose a default threshold for all drives, then customize each storage volume individually below.")
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

    @State private var override: DiskNotificationVolumeOverride

    init(settings: AppSettings, volume: MountedVolume) {
        self.settings = settings
        self.volume = volume
        _override = State(initialValue: settings.diskNotificationOverride(for: volume.mountPath))
    }

    private var volumeSummary: String {
        let freePercent = Int((max(0, 1 - volume.usageFraction) * 100).rounded())
        return "\(MenuBarFormatters.gigabytes(volume.freeSize)) free · \(freePercent)% remaining · \(MenuBarFormatters.gigabytes(volume.totalSize)) total"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.body.weight(.medium))
                    Text(volumeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: settings.diskNotificationVolumeOverrides[volume.mountPath]) { _, newValue in
            if let newValue, newValue != override {
                override = newValue
            }
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
