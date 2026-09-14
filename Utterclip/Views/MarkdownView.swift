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
        /// A line the writer left empty. Kept, because someone who put a gap there meant it.
        case blank
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .font(ResultTypography.font)
        .lineSpacing(ResultTypography.lineSpacing)
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            // Headings step up from the body size rather than from the system's, so the
            // whole block scales together.
            inline(text)
                .font(IdentityFont.text(size: ResultTypography.size + (level <= 1 ? 4 : level == 2 ? 1 : 0),
                                        weight: level == 2 ? .semibold : .bold, relativeTo: .body))
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
        case .blank:
            Color.clear.frame(height: ResultTypography.lineHeight / 2)
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
        var result: [Block] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // An empty line is a gap the writer put there. Dropping them made an edited
            // result come back looking like one run-on block. Runs of them collapse to one,
            // and a leading one is nothing to separate.
            guard !line.isEmpty else {
                if case .blank = result.last { continue }
                if !result.isEmpty { result.append(.blank) }
                continue
            }
            result.append(block(from: line))
        }
        if case .blank = result.last { result.removeLast() }
        return result
    }

    private func block(from line: String) -> Block {
        {

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
        }()
    }
}
