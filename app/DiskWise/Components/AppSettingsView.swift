import SwiftUI
import DiskScannerKit
import AIKit

struct AppSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Text(
                    "Step 1 can run in Fast mode (sizes dependency folders like node_modules in one step) or Deep mode (indexes every file). Steps 2 and 3 limits apply after the filesystem scan."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Filesystem scan (Step 1)") {
                Picker("Scan mode", selection: $settings.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(settings.scanMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Performance preset") {
                Picker("Preset", selection: Binding(
                    get: { settings.activePreset ?? .balanced },
                    set: { settings.applyPreset($0) }
                )) {
                    ForEach(ScanPerformancePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Text(settings.activePreset?.detail ?? "Custom limits — adjust the sliders below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Duplicate detection (Step 2)") {
                limitRow(
                    title: "Files to check",
                    value: $settings.duplicateScanFileLimit,
                    range: AppSettings.duplicateScanFileLimitRange,
                    step: 10_000,
                    help: "Compares the largest files by size. Higher values find more duplicates but take longer."
                )
            }

            Section("Storage analysis (Step 3)") {
                limitRow(
                    title: "Files to analyze",
                    value: $settings.analysisFileLimit,
                    range: AppSettings.analysisFileLimitRange,
                    step: 1_000,
                    help: "Samples the largest files when building cleanup recommendations and AI insights."
                )
            }

            Section("Menu bar monitor") {
                MenuBarVolumeToggleSection(
                    settings: settings,
                    volumes: SystemVolumeMonitor.shared.volumes
                )

                Toggle(
                    "Show health score",
                    isOn: Binding(
                        get: { settings.showMenuBarHealthScore },
                        set: { settings.setMenuBarHealthScoreVisible($0) }
                    )
                )

                Text(MenuBarMonitorController.menuBarMonitorStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.showMenuBarDiskMonitor {
                    Text("Click a menu bar icon for drive details and to show or hide each display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Appearance") {
                Toggle(
                    "Hide DiskWise from Dock",
                    isOn: Binding(
                        get: { settings.hideFromDock },
                        set: { settings.setHideFromDock($0) }
                    )
                )

                Text("When enabled, DiskWise runs from the menu bar without a Dock icon. Open the app from a menu bar item or Spotlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Startup") {
                Toggle(
                    "Open DiskWise at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLoginEnabled($0) }
                    )
                )

                Text(MenuBarMonitorController.launchAtLoginStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if MenuBarMonitorController.launchAtLoginService.status == .requiresApproval {
                    Button("Open Login Items Settings") {
                        MenuBarMonitorController.openLoginItemsSettingsForApproval()
                    }
                }
            }

            Section("AI assistant") {
                Picker("Provider", selection: $settings.aiProviderPreference) {
                    Text("Automatic").tag(AIProviderKind.automatic)
                    Text("Apple Intelligence").tag(AIProviderKind.foundationModels)
                    Text("Ollama (developer)").tag(AIProviderKind.ollama)
                    Text("Rule-based only").tag(AIProviderKind.ruleBased)
                }

                Toggle("Enable Ollama developer mode", isOn: $settings.enableOllamaDevMode)

                TextField("Ollama base URL", text: $settings.ollamaBaseURL)
                    .disabled(!settings.enableOllamaDevMode)

                TextField("Ollama model", text: $settings.ollamaModel)
                    .disabled(!settings.enableOllamaDevMode)

                Text("Automatic prefers Apple Intelligence on supported Macs, then local MLX models, then Ollama when developer mode is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Restore defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 500)
        .navigationTitle("Settings")
        .onAppear {
            SystemVolumeMonitor.shared.refresh()
        }
        .sheet(isPresented: $settings.showMenuBarMonitorInstructions) {
            MenuBarMonitorInstructionSheet()
        }
    }

    @ViewBuilder
    private func limitRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted())
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
