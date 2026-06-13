import AppKit
import DiskScannerKit
import SwiftUI

enum PythonSetupWizardStep: Equatable {
    case needsSetup
    case waiting
    case ready
}

enum PythonSetupSupport {
    static func openInstallScriptInTerminal() {
        guard let scriptURL = PythonScanRunner.bundledInstallScriptURL() else { return }

        let escapedPath = scriptURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "bash '\\(escapedPath)'"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
    }

    static func openPythonDownloadsPage() {
        if let url = URL(string: "https://www.python.org/downloads/macos/") {
            NSWorkspace.shared.open(url)
        }
    }

    static var installScriptPath: String? {
        PythonScanRunner.bundledInstallScriptURL()?.path
    }
}

struct PythonSetupGateOverlay: View {
    let step: PythonSetupWizardStep
    let onInstall: () -> Void
    let onDismiss: () -> Void
    let onCancelWaiting: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            PythonSetupPromptView(
                step: step,
                onInstall: onInstall,
                onDismiss: onDismiss,
                onCancelWaiting: onCancelWaiting
            )
            .padding(28)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(32)
        }
        .transition(.opacity)
        .zIndex(100)
    }
}

struct PythonSetupPromptView: View {
    let step: PythonSetupWizardStep
    let onInstall: () -> Void
    let onDismiss: () -> Void
    let onCancelWaiting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            GroupBox {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }

            footer
        }
        .padding(28)
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbol)
                .font(.system(size: 34))
                .foregroundStyle(headerColor)
                .symbolEffect(.pulse, isActive: step == .waiting)

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.title2.bold())
                Text(headerSubtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .needsSetup:
            VStack(alignment: .leading, spacing: 12) {
                Text("DiskWise uses a Python scanner for fast, reliable disk indexing. Python 3 was not found on this Mac.")

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(number: 1, text: "Click Install in Terminal below")
                    instructionRow(number: 2, text: "Follow the prompts — the script installs Python via Homebrew when available")
                    instructionRow(number: 3, text: "Return to DiskWise — scanning starts working automatically")
                }
                .foregroundStyle(.secondary)

                if let scriptPath = PythonSetupSupport.installScriptPath {
                    Text(scriptPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }

                Text("No Homebrew? The script opens python.org so you can download the official installer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .waiting:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Waiting for Python…")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(number: 1, text: "Complete the install steps in Terminal")
                    instructionRow(number: 2, text: "If Homebrew asks for your password, enter your Mac login password")
                    instructionRow(number: 3, text: "Return here when the script finishes — DiskWise detects Python automatically")
                }
                .foregroundStyle(.secondary)
            }

        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                Label("Python 3 detected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Ready to scan drives…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .needsSetup:
            HStack {
                Button("Install in Terminal", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                Button("Download from python.org") {
                    PythonSetupSupport.openPythonDownloadsPage()
                }

                Spacer()

                Button("Not Now", action: onDismiss)
            }

        case .waiting:
            HStack {
                Button("Open Terminal Again", action: onInstall)

                Button("Download from python.org") {
                    PythonSetupSupport.openPythonDownloadsPage()
                }

                Spacer()

                Button("Not Now", action: onCancelWaiting)
            }

        case .ready:
            EmptyView()
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.caption.monospaced())
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.subheadline)
        }
    }

    private var headerSymbol: String {
        switch step {
        case .needsSetup: "terminal"
        case .waiting: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle"
        }
    }

    private var headerColor: Color {
        switch step {
        case .needsSetup: .orange
        case .waiting: .blue
        case .ready: .green
        }
    }

    private var headerTitle: String {
        switch step {
        case .needsSetup: "Python 3 required for scanning"
        case .waiting: "Installing Python"
        case .ready: "Python ready"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .needsSetup:
            return "One-time setup — about 2 minutes."
        case .waiting:
            return "DiskWise will detect Python when installation completes."
        case .ready:
            return "You can scan drives now."
        }
    }
}

struct PythonSetupBanner: View {
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Python 3 required", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Install Python to enable fast disk scanning. Use the one-click installer in Terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Install Python", action: onInstall)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
