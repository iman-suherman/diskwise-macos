import SwiftUI
import DiskScannerKit
import AIKit

struct AppSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var menuBarExtensionInstallError: String?

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

            if MenuBarExtensionInstaller.isHelperBundled {
                Section("Menu bar monitor") {
                    Toggle(
                        "Show disk space in menu bar",
                        isOn: Binding(
                            get: { settings.isMenuBarExtensionInstalled },
                            set: { setMenuBarExtensionEnabled($0) }
                        )
                    )

                    Text("Displays Macintosh HD usage with a percentage and bar chart. Starts automatically when you log in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(MenuBarExtensionInstaller.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let menuBarExtensionInstallError {
                        Text(menuBarExtensionInstallError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if MenuBarExtensionInstaller.service.status == .requiresApproval {
                        Button("Open Login Items Settings") {
                            MenuBarExtensionInstaller.openLoginItemsSettingsForApproval()
                        }
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
    }

    private func setMenuBarExtensionEnabled(_ enabled: Bool) {
        menuBarExtensionInstallError = nil
        do {
            if enabled {
                try MenuBarExtensionInstaller.install()
            } else {
                try MenuBarExtensionInstaller.uninstall()
            }
        } catch {
            menuBarExtensionInstallError = error.localizedDescription
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
