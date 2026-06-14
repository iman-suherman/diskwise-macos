import AIKit
import SwiftUI

struct MemoryInsightSection: Identifiable {
    let id: String
    let title: String?
    let items: [MemoryInsightItem]
}

enum MemoryInsightItem: Identifiable {
    case paragraph(String)
    case subheading(String)
    case bullet(title: String?, body: String)
    case metric(label: String, value: String)
    case tip(number: Int, title: String, body: String)

    var id: String {
        switch self {
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        case .subheading(let text):
            return "s-\(text.hashValue)"
        case .bullet(let title, let body):
            return "b-\(title ?? "")-\(body.hashValue)"
        case .metric(let label, let value):
            return "m-\(label)-\(value)"
        case .tip(let number, let title, let body):
            return "t-\(number)-\(title)-\(body.hashValue)"
        }
    }
}

struct MemoryInsightStreamingView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if text.isEmpty && isStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing memory patterns…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isStreaming {
                    MemoryInsightStreamingCursor()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MemoryInsightContentView: View {
    let text: String
    var report: MemoryAnalysisReport?
    var onPerformAction: ((MemoryActionRecommendation) -> Void)?

    private var sections: [MemoryInsightSection] {
        ChatMessageFormatter.parseMemoryInsight(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections) { section in
                sectionView(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionView(_ section: MemoryInsightSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = section.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                itemView(item)
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: MemoryInsightItem) -> some View {
        switch item {
        case .paragraph(let text):
            insightMarkdown(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .subheading(let text):
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, 4)

        case .metric(let label, let value):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .bullet(let title, let body):
            actionRow(
                icon: "lightbulb",
                title: title,
                body: body,
                recommendation: resolvedRecommendation(title: title, body: body)
            )

        case .tip(let number, let title, let body):
            actionRow(
                icon: "\(number).circle.fill",
                title: title,
                body: body,
                recommendation: resolvedRecommendation(title: title, body: body),
                numbered: number
            )
        }
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        title: String?,
        body: String,
        recommendation: MemoryActionRecommendation?,
        numbered: Int? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let numbered {
                    Text("\(numbered).")
                        .font(.caption.weight(.bold).monospacedDigit())
                } else {
                    Image(systemName: icon)
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 20, alignment: numbered == nil ? .center : .trailing)
            .padding(.top, numbered == nil ? 1 : 2)

            VStack(alignment: .leading, spacing: 4) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let recommendation, let onPerformAction {
                insightActionButton(for: recommendation, action: onPerformAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func insightActionButton(
        for recommendation: MemoryActionRecommendation,
        action: @escaping (MemoryActionRecommendation) -> Void
    ) -> some View {
        if let title = MemoryActionExecutor.actionTitle(for: recommendation) {
            if recommendation.actionKind == .freeMemory {
                Button(title) {
                    action(recommendation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(title) {
                    action(recommendation)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func resolvedRecommendation(title: String?, body: String) -> MemoryActionRecommendation? {
        guard let report else { return nil }
        return MemoryInsightActionMatcher.recommendation(forTitle: title, body: body, report: report)
    }

    @ViewBuilder
    private func insightMarkdown(_ text: String) -> some View {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Text(cleaned)
            .lineSpacing(4)
            .textSelection(.enabled)
    }
}

private struct MemoryInsightStreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 16)
            .opacity(visible ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}
