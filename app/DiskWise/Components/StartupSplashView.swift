import AppKit
import SwiftUI

struct StartupSplashOverlay: View {
    let version: String
    let isPostUpgrade: Bool
    let currentMessage: String
    let completedSteps: Set<StartupStep>
    let activeStep: StartupStep?

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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .animation(.easeInOut(duration: 0.2), value: currentMessage)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(StartupStep.allCases) { step in
                        startupStepRow(step)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 8)
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
    case drives
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .database: return "Open database"
        case .drives: return "Discover drives"
        case .permissions: return "Check permissions"
        }
    }

    var icon: String {
        switch self {
        case .database: return "cylinder"
        case .drives: return "externaldrive"
        case .permissions: return "lock.shield"
        }
    }
}
