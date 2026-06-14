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

enum MemoryFormattedContentKind {
    case insight
    case chat
}

struct MemoryInsightRenderedView: View {
    let text: String
    var kind: MemoryFormattedContentKind = .insight
    var font: Font = .subheadline

    private var sections: [MemoryInsightSection] {
        switch kind {
        case .insight:
            return ChatMessageFormatter.parseMemoryInsight(text)
        case .chat:
            return ChatMessageFormatter.parseMemoryChat(text)
        }
    }

    var body: some View {
        Group {
            if sections.isEmpty {
                DiskWiseMarkdownText(
                    text: text,
                    font: font,
                    format: kind == .chat ? .memoryChat : .memoryInsight
                )
            } else {
                VStack(alignment: .leading, spacing: kind == .chat ? 12 : 16) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionView(_ section: MemoryInsightSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = section.title, !title.isEmpty {
                Text(title)
                    .font(font.weight(.semibold))
            }

            ForEach(section.items) { item in
                itemView(item)
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: MemoryInsightItem) -> some View {
        switch item {
        case .paragraph(let text):
            insightMarkdown(text)
        case .subheading(let text):
            Text(text)
                .font(font == .subheadline ? .caption.weight(.semibold) : font.weight(.semibold))
                .foregroundStyle(.secondary)
        case .bullet(let title, let body):
            bulletRow(title: title, body: body)
        case .metric(let label, let value):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label):")
                    .fontWeight(.semibold)
                Text(value)
                    .foregroundStyle(.secondary)
            }
            .font(font)
        case .tip(let number, let title, let body):
            VStack(alignment: .leading, spacing: 3) {
                Text("Tip \(number): \(title)")
                    .font(font.weight(.semibold))
                Text(body)
                    .font(font == .subheadline ? .caption : font)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func bulletRow(title: String?, body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color.accentColor)
                .font(font.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(font.weight(.semibold))
                }
                if !body.isEmpty {
                    insightMarkdown(body)
                }
            }
        }
    }

    @ViewBuilder
    private func insightMarkdown(_ text: String) -> some View {
        DiskWiseMarkdownText(
            text: text,
            font: font,
            foregroundStyle: kind == .insight ? .secondary : nil,
            format: kind == .chat ? .memoryChat : .chat
        )
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
            } else if isStreaming {
                DiskWiseMarkdownText(
                    text: text,
                    font: .subheadline,
                    foregroundStyle: .secondary,
                    format: .memoryInsight
                )

                MemoryInsightStreamingCursor()
            } else {
                MemoryInsightRenderedView(text: text)
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

    private var actionableItems: [(MemoryInsightItem, MemoryActionRecommendation)] {
        guard let report else { return [] }
        return sections.flatMap(\.items).compactMap { item in
            guard let recommendation = recommendation(for: item, report: report),
                  MemoryActionExecutor.actionTitle(for: recommendation) != nil else {
                return nil
            }
            return (item, recommendation)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MemoryInsightRenderedView(text: text)

            if !actionableItems.isEmpty, let onPerformAction {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(actionableItems.enumerated()), id: \.offset) { _, entry in
                        actionRow(
                            item: entry.0,
                            recommendation: entry.1,
                            action: onPerformAction
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionRow(
        item: MemoryInsightItem,
        recommendation: MemoryActionRecommendation,
        action: @escaping (MemoryActionRecommendation) -> Void
    ) -> some View {
        switch item {
        case .bullet(let title, let body):
            actionRowContent(title: title, body: body, recommendation: recommendation, action: action)
        case .tip(_, let title, let body):
            actionRowContent(title: title, body: body, recommendation: recommendation, action: action)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func actionRowContent(
        title: String?,
        body: String,
        recommendation: MemoryActionRecommendation,
        action: @escaping (MemoryActionRecommendation) -> Void
    ) -> some View {
            HStack(alignment: .top, spacing: 12) {
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

                insightActionButton(for: recommendation, action: action)
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

    private func recommendation(for item: MemoryInsightItem, report: MemoryAnalysisReport) -> MemoryActionRecommendation? {
        switch item {
        case .bullet(let title, let body):
            return MemoryInsightActionMatcher.recommendation(forTitle: title, body: body, report: report)
        case .tip(_, let title, let body):
            return MemoryInsightActionMatcher.recommendation(forTitle: title, body: body, report: report)
        default:
            return nil
        }
    }
}

struct MemoryInsightStreamingCursor: View {
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
