import SwiftUI
import DiskScannerKit
import AIKit

enum AppSettingsTab: String, CaseIterable, Identifiable {
    case scanning
    case menuBar
    case general
    case memory
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanning: return "Scanning"
        case .menuBar: return "Menu Bar"
        case .general: return "General"
        case .memory: return "Memory"
        case .ai: return "AI"
        }
    }

    var icon: String {
        switch self {
        case .scanning: return "arrow.triangle.2.circlepath"
        case .menuBar: return "menubar.rectangle"
        case .general: return "gearshape"
        case .memory: return "memorychip"
        case .ai: return "sparkles"
        }
    }
}

extension AppSettingsTab: DiskWiseTabRepresentable {}

struct AppSettingsView: View {
    @ObservedObject var settings: AppSettings
    var embeddedInPanel: Bool = false

    @State private var selectedTab: AppSettingsTab = .scanning

    var body: some View {
        Group {
            if embeddedInPanel {
                VStack(spacing: 0) {
                    embeddedHeader
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        .padding(.bottom, 12)

                    DiskWiseIconTabBar(selection: $selectedTab)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)

                    ScrollView {
                        selectedTabForm
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 0) {
                    DiskWiseIconTabBar(selection: $selectedTab)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ScrollView {
                        selectedTabForm
                            .padding(.horizontal, 4)
                            .padding(.bottom, 12)
                    }
                    .frame(width: 560, height: 480)
                }
                .navigationTitle("Settings")
            }
        }
        .sheet(isPresented: $settings.showMenuBarMonitorInstructions) {
            MenuBarMonitorInstructionSheet()
        }
        .onAppear {
            SystemVolumeMonitor.shared.refresh()
        }
    }

    private var embeddedHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.largeTitle.bold())
            Text("Scan limits, AI provider, menu bar monitor, and preferences.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedTabForm: some View {
        switch selectedTab {
        case .scanning:
            scanningForm
        case .menuBar:
            menuBarForm
        case .general:
            generalForm
        case .memory:
            memoryForm
        case .ai:
            aiForm
        }
    }

    private var scanningForm: some View {
        Form {
            Section {
                Text(
                    "Step 1 always starts with Fast scan unless you choose Deep scan when indexing a drive. Adjust duplicate and analysis limits below for steps 2 and 3."
                )
                .font(.subheadline)
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
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuBarForm: some View {
        Form {
            Section("Menu bar monitor") {
                HStack(alignment: .top, spacing: 24) {
                    MenuBarKeepAwakeSection(
                        settings: settings,
                        volumes: SystemVolumeMonitor.shared.volumes
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    MenuBarVolumeToggleSection(
                        settings: settings,
                        volumes: SystemVolumeMonitor.shared.volumes,
                        showsSectionTitle: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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

                Toggle(
                    "Alert when disk space is low",
                    isOn: $settings.diskSpaceNotificationsEnabled
                )

                Toggle(
                    "Alert when system health is poor",
                    isOn: $settings.systemHealthNotificationsEnabled
                )

                Text("Notifies when any mounted drive (except tiny app disk images) drops below 10% free or below 100 GB free — whichever threshold is lower for that drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalForm: some View {
        Form {
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

            Section {
                Button("Restore defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryForm: some View {
        Form {
            Section("Memory Analyzer") {
                Toggle("Monitor memory in the background", isOn: $settings.memoryAnalyzerEnabled)

                Toggle(
                    "Notify when new insights are available",
                    isOn: $settings.memoryAnalyzerNotificationsEnabled
                )
                .disabled(!settings.memoryAnalyzerEnabled)

                Text("DiskWise samples memory every 20–30 seconds, runs periodic Apple Intelligence analysis, and can notify you with a one-tap action when a new recommendation is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiForm: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
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
