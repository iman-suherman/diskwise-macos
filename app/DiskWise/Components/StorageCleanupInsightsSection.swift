import AIKit
import DatabaseKit
import SwiftUI

struct StorageCleanupInsightsSection: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let report: AnalysisReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            appleIntelligenceSummaryCard
            sectionBySectionActions
        }
    }

    private var appleIntelligenceSummaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Apple Intelligence Cleanup Plan", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text("Up to \(DiskWiseFormatters.bytes.string(fromByteCount: report.potentialReclaimableSpace))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if viewModel.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing indexed files…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.aiAnalysisSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(viewModel.aiProviderStatus.displayName, systemImage: "brain.head.profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(viewModel.aiAnalysisSummary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                } else if viewModel.aiProviderStatus.isGenerativeAvailable {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Apple Intelligence is preparing cleanup suggestions…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                let savingsInsights = report.insights.filter { $0.estimatedSavings > 0 }
                if !savingsInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(savingsInsights) { insight in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(DiskWiseFormatters.bytes.string(fromByteCount: insight.estimatedSavings)) — \(insight.title)")
                                        .font(.subheadline.weight(.medium))
                                    Text(insight.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sectionBySectionActions: some View {
        ForEach(ActionBucket.allCases) { bucket in
            let items = report.recommendationsByBucket[bucket, default: []]
            if !items.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(bucket.title, systemImage: bucket.icon)
                            .font(.headline)
                            .foregroundStyle(bucketColor(bucket))

                        Text(bucket.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if bucketSavings(bucket, report: report) > 0 {
                            Text("About \(DiskWiseFormatters.bytes.string(fromByteCount: bucketSavings(bucket, report: report))) in this section")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, recommendation in
                                RecommendationActionCard(recommendation: recommendation, bucket: bucket) {
                                    viewModel.handleRecommendation(recommendation)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func bucketSavings(_ bucket: ActionBucket, report: AnalysisReport) -> Int64 {
        report.savings(for: bucket)
    }

    private func bucketColor(_ bucket: ActionBucket) -> Color {
        switch bucket {
        case .safeRegenerable: return .green
        case .reviewFirst: return .orange
        case .personalKeep: return .blue
        }
    }
}

struct RecommendationActionCard: View {
    let recommendation: RecommendationRecord
    let bucket: ActionBucket
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(recommendation.title)
                    .font(.headline)
                Spacer()
                Text(bucket.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(bucketBadgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(bucketBadgeColor)
            }
            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if recommendation.estimatedSavings > 0 {
                    Text("Save \(DiskWiseFormatters.bytes.string(fromByteCount: recommendation.estimatedSavings))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(bucket == .personalKeep ? "Review" : "Take Action") {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bucketBadgeColor: Color {
        switch bucket {
        case .safeRegenerable: return .green
        case .reviewFirst: return .orange
        case .personalKeep: return .blue
        }
    }
}
