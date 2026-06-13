import DiskScannerKit
import SwiftUI

enum IndexRebuildStep: String, CaseIterable, Identifiable {
    case clearing
    case identifying
    case analyzing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearing: return "Clear saved storage index"
        case .identifying: return "Identify disk usage on APFS volumes"
        case .analyzing: return "Analyze into safe, review, and personal buckets"
        }
    }

    var icon: String {
        switch self {
        case .clearing: return "trash.circle"
        case .identifying: return "doc.text.magnifyingglass"
        case .analyzing: return "sparkles"
        }
    }
}

struct IndexRebuildProgressOverlay: View {
    let version: String
    let volumeName: String?
    let currentMessage: String
    let completedSteps: Set<IndexRebuildStep>
    let activeStep: IndexRebuildStep?
    let scanProgress: ScanProgress?

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 6) {
                    Text("Rebuilding storage index")
                        .font(.title2.bold())
                    if let volumeName {
                        Text("DiskWise \(version) · \(volumeName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("DiskWise \(version)")
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
                    .frame(maxWidth: 420)
                    .animation(.easeInOut(duration: 0.2), value: currentMessage)

                if let scanProgress, activeStep == .identifying {
                    VStack(spacing: 6) {
                        if let detail = scanProgress.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        HStack(spacing: 16) {
                            Label(scanProgress.operation.label, systemImage: "gearshape")
                            Label(scanProgress.scannedCount.formatted(), systemImage: "doc.text")
                            Label(
                                ByteCountFormatter.string(fromByteCount: scanProgress.bytesIndexed, countStyle: .file),
                                systemImage: "externaldrive"
                            )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(IndexRebuildStep.allCases) { step in
                        rebuildStepRow(step)
                    }
                    Label("Take action via individual Maintenance tools", systemImage: "4.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 420, alignment: .leading)
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
        .zIndex(102)
    }

    @ViewBuilder
    private func rebuildStepRow(_ step: IndexRebuildStep) -> some View {
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

struct IndexRebuildOverlay: View {
    let version: String
    let onRebuild: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Rebuild storage index?")
                        .font(.title2.bold())
                    Text("DiskWise \(version) uses a new three-phase cleanup model. Your saved index was built with the previous pipeline and should be rebuilt for accurate recommendations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Identify disk usage on APFS volumes", systemImage: "1.circle.fill")
                    Label("Analyze into safe, review, and personal buckets", systemImage: "2.circle.fill")
                    Label("Take action via individual Maintenance tools", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.top, 4)

                HStack(spacing: 12) {
                    Button("Not Now") {
                        onSkip()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Rebuild Index") {
                        onRebuild()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
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
        .zIndex(101)
    }
}
