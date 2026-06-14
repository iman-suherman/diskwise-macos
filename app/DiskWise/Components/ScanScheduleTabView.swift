import DiskScannerKit
import SwiftUI

struct VolumeScanScheduleRecommendationSection: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var embeddedInScanPanel = false

    var body: some View {
        if viewModel.hasVolumeScanScheduleEnabled {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Recommended schedule", systemImage: "calendar.badge.clock")
                    .font(embeddedInScanPanel ? .headline : .subheadline.weight(.semibold))

                Text("Turn on automatic fast and deep scans so DiskWise refreshes this drive when your Mac is idle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                recommendationRows

                HStack(spacing: 10) {
                    Button {
                        viewModel.applyRecommendedScanSchedule()
                    } label: {
                        Label("Enable recommended schedule", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Customize…") {
                        viewModel.openScheduleTab()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(embeddedInScanPanel ? 14 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var recommendationRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ScanScheduleAdvisor.recommendedEntries()) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.mode == .deep ? "scope" : "bolt.fill")
                        .foregroundStyle(entry.mode == .deep ? .orange : .yellow)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.title): \(ScanScheduleAdvisor.entrySummary(entry))")
                            .font(.caption.weight(.semibold))
                        Text(entry.mode == .deep ? ScanScheduleAdvisor.deepScanRationale() : ScanScheduleAdvisor.fastScanRationale())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ScanScheduleTabView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.selectedVolume == nil {
                    ContentUnavailableView {
                        Label("Select a drive", systemImage: "internaldrive")
                    } description: {
                        Text("Choose a drive to configure scheduled fast and deep scans.")
                    }
                    .padding(.vertical, 24)
                } else {
                    headerSection
                    schedulesSection
                    actionsSection
                }
            }
            .padding(.bottom, 28)
        }
        .onAppear {
            viewModel.reloadVolumeScanSchedule()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.title2.bold())
            if let volume = viewModel.selectedVolume {
                Text("\(volume.name) — run multiple fast and deep scans automatically at times you choose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var schedulesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Scan schedules", systemImage: "calendar")
                    .font(.headline)

                if viewModel.volumeScanSchedule.entries.isEmpty {
                    Text("No schedules yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($viewModel.volumeScanSchedule.entries) { $entry in
                        scheduleEntryEditor(entry: $entry)
                        if entry.id != viewModel.volumeScanSchedule.entries.last?.id {
                            Divider()
                        }
                    }
                }

                Menu {
                    Button {
                        viewModel.addScheduleEntry(mode: .fast)
                    } label: {
                        Label("Fast scan", systemImage: "bolt.fill")
                    }
                    Button {
                        viewModel.addScheduleEntry(mode: .deep)
                    } label: {
                        Label("Deep scan", systemImage: "scope")
                    }
                } label: {
                    Label("Add schedule", systemImage: "plus.circle")
                }
                .disabled(viewModel.selectedVolume == nil)
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.applyRecommendedScanSchedule()
            } label: {
                Label("Enable recommended", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)

            if viewModel.hasVolumeScanScheduleEnabled {
                Button("Run all now") {
                    viewModel.runAllEnabledSchedulesNow()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct scheduleEntryEditor: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Binding var entry: ScanScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(entry.title, systemImage: entry.mode == .deep ? "scope" : "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.mode == .deep ? .orange : Color.accentColor)
                Spacer()
                Toggle("Enabled", isOn: $entry.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: entry.isEnabled) { _, _ in
                        viewModel.persistVolumeScanScheduleFromBindings()
                    }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker("Hour", selection: $entry.hour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(ScanScheduleAdvisor.timeLabel(hour: hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)

                        Picker("Minute", selection: $entry.minute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 72)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Frequency")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(ScanScheduleAdvisor.frequencyPresets(), id: \.title) { preset in
                            Button(preset.title) {
                                entry.weekdays = preset.weekdays
                                viewModel.persistVolumeScanScheduleFromBindings()
                            }
                        }
                    } label: {
                        Text(ScanScheduleAdvisor.weekdaySummary(entry.weekdays))
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            weekdayPicker

            if viewModel.volumeScanSchedule.entries.count > 1 {
                Button("Remove", role: .destructive) {
                    viewModel.removeScheduleEntry(id: entry.id)
                }
                .font(.caption)
            }
        }
        .onChange(of: entry.hour) { _, _ in viewModel.persistVolumeScanScheduleFromBindings() }
        .onChange(of: entry.minute) { _, _ in viewModel.persistVolumeScanScheduleFromBindings() }
        .onChange(of: entry.weekdays) { _, _ in viewModel.persistVolumeScanScheduleFromBindings() }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(ScanScheduleAdvisor.weekdayOptions(), id: \.value) { option in
                let isSelected = entry.weekdays.contains(option.value)
                Button {
                    toggleWeekday(option.value)
                } label: {
                    Text(String(option.label.prefix(1)))
                        .font(.caption2.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .help(option.label)
            }
        }
    }

    private func toggleWeekday(_ weekday: Int) {
        if entry.weekdays.contains(weekday) {
            entry.weekdays.removeAll { $0 == weekday }
        } else {
            entry.weekdays.append(weekday)
            entry.weekdays.sort()
        }
        viewModel.persistVolumeScanScheduleFromBindings()
    }
}
