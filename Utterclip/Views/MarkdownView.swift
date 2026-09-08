import SwiftUI

/// Renders the markdown subset the rewrite styles produce (headings, bullet/numbered
/// lists, bold/italic/code) as formatted SwiftUI text instead of literal characters.
struct MarkdownView: View {
    let markdown: String

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case ordered(String, String) // marker ("1."), text
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 2)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inline(text)
            }
        case .ordered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                inline(text)
            }
        case .paragraph(let text):
            inline(text)
        }
    }

    /// Inline markdown (bold/italic/code) via Foundation's parser; falls back to the
    /// literal string if parsing fails.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }

    private var blocks: [Block] {
        markdown.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }

            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                let text = line.dropFirst(hashes.count)
                if text.first == " " {
                    return .heading(min(hashes.count, 6), String(text.dropFirst()))
                }
            }
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return .bullet(String(line.dropFirst(marker.count)))
            }
            if let range = line.range(of: #"^\d{1,3}\. "#, options: .regularExpression) {
                return .ordered(
                    String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces),
                    String(line[range.upperBound...]))
            }
            return .paragraph(line)
        }
    }
}
