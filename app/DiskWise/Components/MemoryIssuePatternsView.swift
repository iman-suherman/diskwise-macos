import AIKit
import SwiftUI

struct MemoryIssuePatternsView: View {
    @ObservedObject private var monitor = MemoryAnalyzerMonitor.shared
    @ObservedObject private var historyStore = MemoryIssueHistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            headerSection
            historyTableSection
            aiAnalysisSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if historyStore.patterns.isEmpty == false, monitor.issuePatternAISummary.isEmpty {
                monitor.refreshIssuePatternAnalysis()
            }
        }
        .onChange(of: historyStore.patterns.count) { _, count in
            guard count > 0 else { return }
            monitor.refreshIssuePatternAnalysis()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issue History")
                .font(.title2.bold())

            Text(
                "Similar memory alerts are grouped here. DiskWise records every recurrence but only notifies you when the gap since the last alert is long (about 4 hours)."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var historyTableSection: some View {
        if historyStore.patterns.isEmpty {
            ContentUnavailableView {
                Label("No recurring issues yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("When Memory Analyzer detects the same issue multiple times, it will appear here with occurrence counts and typical intervals.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Historical behaviour")
                    .font(.headline)

                VStack(spacing: 0) {
                    tableHeader
                    Divider()
                    ForEach(historyStore.patterns) { pattern in
                        tableRow(for: pattern)
                        if pattern.id != historyStore.patterns.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            headerCell("Issue", width: 180)
            headerCell("Count", width: 52)
            headerCell("Avg interval", width: 88)
            headerCell("Median", width: 72)
            headerCell("Last seen", width: 120)
            headerCell("Typical RAM", width: 72)
            headerCell("Alerts", width: 52)
            headerCell("Suppressed", width: 72)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func tableRow(for pattern: MemoryIssuePatternSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(actionLabel(for: pattern.actionKind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .leading)

            valueCell("\(pattern.occurrenceCount)", width: 52)
            valueCell(MemoryIssuePatternAnalyzer.formatInterval(pattern.averageInterval), width: 88)
            valueCell(MemoryIssuePatternAnalyzer.formatInterval(pattern.medianInterval), width: 72)
            valueCell(relativeDate(pattern.lastSeenAt), width: 120)
            valueCell("\(Int(pattern.typicalMemoryUsedPercent.rounded()))%", width: 72)
            valueCell("\(pattern.notificationCount)", width: 52)
            valueCell("\(pattern.suppressedNotificationCount)", width: 72)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI pattern analysis")
                    .font(.headline)
                Spacer()
                Button {
                    monitor.refreshIssuePatternAnalysis()
                } label: {
                    Label("Analyze", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(historyStore.patterns.isEmpty || monitor.isAnalyzingIssuePatterns)
            }

            if historyStore.patterns.isEmpty {
                Text("Collect a few recurring issues first, then DiskWise can suggest better habits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if monitor.isAnalyzingIssuePatterns, monitor.issuePatternAISummary.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing patterns…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !monitor.issuePatternAISummary.isEmpty {
                MemoryInsightRenderedView(text: monitor.issuePatternAISummary)
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(MemoryIssuePatternEngine.ruleBasedAnalysis(for: historyStore.patterns))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func valueCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.subheadline.monospacedDigit())
            .frame(width: width, alignment: .leading)
    }

    private func actionLabel(for kind: MemoryActionKind) -> String {
        switch kind {
        case .quitProcess: return "Quit app"
        case .freeMemory: return "Free memory"
        case .restartApp: return "Restart app"
        case .reduceTabs: return "Focus app"
        case .informational: return "Information"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
