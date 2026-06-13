import AppKit
import SwiftUI

struct StartupSplashOverlay: View {
    let version: String
    let isPostUpgrade: Bool
    let migratesScanFormat: Bool
    let prewarmsSavedScan: Bool
    let profilesSystemHealth: Bool
    let includesAIInsights: Bool
    let currentMessage: String
    let highlightMessage: Bool
    let completedSteps: Set<StartupStep>
    let activeStep: StartupStep?
    var showSkipPrewarm = false
    var onSkipPrewarm: (() -> Void)?

    private var visibleSteps: [StartupStep] {
        StartupStep.visibleSteps(
            migratesScanFormat: migratesScanFormat,
            prewarmSavedScan: prewarmsSavedScan,
            profilesSystemHealth: profilesSystemHealth,
            includeAIInsights: includesAIInsights
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)

                VStack(spacing: 6) {
                    Text(isPostUpgrade ? "Setting up DiskWise \(version)" : "Starting DiskWise")
                        .font(.title2.bold())

                    if isPostUpgrade {
                        Text("First launch after the update")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView()
                    .controlSize(.regular)
                    .padding(.top, 4)

                Text(currentMessage)
                    .font(.subheadline.weight(highlightMessage ? .semibold : .medium))
                    .foregroundStyle(highlightMessage ? Color.orange : Color.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.horizontal, highlightMessage ? 12 : 0)
                    .padding(.vertical, highlightMessage ? 8 : 0)
                    .background {
                        if highlightMessage {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: currentMessage)
                    .animation(.easeInOut(duration: 0.2), value: highlightMessage)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleSteps) { step in
                        startupStepRow(step)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 8)

                if showSkipPrewarm, let onSkipPrewarm {
                    Button("Skip loading saved scan") {
                        onSkipPrewarm()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)

                    Text("DiskWise will open and ask whether to load your saved scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(40)
        }
        .transition(.opacity)
        .zIndex(100)
    }

    @ViewBuilder
    private func startupStepRow(_ step: StartupStep) -> some View {
        let isComplete = completedSteps.contains(step)
        let isActive = activeStep == step

        HStack(spacing: 10) {
            Group {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isActive {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, height: 18)

            Label(step.title, systemImage: step.icon)
                .font(.subheadline)
                .foregroundStyle(isComplete || isActive ? .primary : .secondary)
                .labelStyle(.titleAndIcon)
        }
    }
}

enum StartupStep: String, CaseIterable, Identifiable {
    case database
    case migrateScanFormat
    case drives
    case permissions
    case python
    case systemHealth
    case savedScan
    case aiProvider
    case aiInsights

    var id: String { rawValue }

    static func visibleSteps(
        migratesScanFormat: Bool,
        prewarmSavedScan: Bool,
        profilesSystemHealth: Bool,
        includeAIInsights: Bool
    ) -> [StartupStep] {
        var steps: [StartupStep] = [.database]
        if migratesScanFormat {
            steps.append(.migrateScanFormat)
        }
        steps.append(contentsOf: [.drives, .permissions, .python])
        if profilesSystemHealth {
            steps.append(.systemHealth)
        }
        if prewarmSavedScan {
            steps.append(.savedScan)
        }
        steps.append(.aiProvider)
        if includeAIInsights {
            steps.append(.aiInsights)
        }
        return steps
    }

    var title: String {
        switch self {
        case .database: return "Open database"
        case .migrateScanFormat: return "Update saved scan format"
        case .drives: return "Discover drives"
        case .permissions: return "Check permissions"
        case .python: return "Check Python scanner"
        case .systemHealth: return "Read system health"
        case .savedScan: return "Load saved scan"
        case .aiProvider: return "Check AI provider"
        case .aiInsights: return "Prepare AI suggestions"
        }
    }

    var icon: String {
        switch self {
        case .database: return "cylinder"
        case .migrateScanFormat: return "arrow.triangle.2.circlepath"
        case .drives: return "externaldrive"
        case .permissions: return "lock.shield"
        case .python: return "terminal"
        case .systemHealth: return "heart.text.square"
        case .savedScan: return "chart.pie"
        case .aiProvider: return "sparkles"
        case .aiInsights: return "text.bubble"
        }
    }
}
