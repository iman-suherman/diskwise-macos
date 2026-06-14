import SwiftUI

struct MemoryInsightSection: Identifiable {
    let id: String
    let title: String?
    let items: [MemoryInsightItem]
}

enum MemoryInsightItem: Identifiable {
    case paragraph(String)
    case bullet(title: String?, body: String)
    case metric(label: String, value: String)
    case tip(number: Int, title: String, body: String)

    var id: String {
        switch self {
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        case .bullet(let title, let body):
            return "b-\(title ?? "")-\(body.hashValue)"
        case .metric(let label, let value):
            return "m-\(label)-\(value)"
        case .tip(let number, let title, let body):
            return "t-\(number)-\(title)-\(body.hashValue)"
        }
    }
}

struct MemoryInsightContentView: View {
    let text: String

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
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .tip(let number, let title, let body):
            HStack(alignment: .top, spacing: 10) {
                Text("\(number).")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private func insightMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            Text(text)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
