import SwiftUI
import UIKit

enum EPTheme {
    static let primary = Color(red: 0.941, green: 0.243, blue: 0.431)
    static let rose = Color(red: 0.957, green: 0.122, blue: 0.416)
    static let fuchsia = Color(red: 0.753, green: 0.192, blue: 0.831)
    static let ink = Color(.label)
    static let muted = Color(.secondaryLabel)
    static let card = Color(.secondarySystemGroupedBackground)
    static let subtle = Color(.tertiarySystemGroupedBackground)

    static func color(hex: String, fallback: Color = .pink) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else { return fallback }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else { return fallback }

        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

struct EPWebCard<Content: View>: View {
    var padding: CGFloat = 16
    var content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.16), lineWidth: 1)
            )
    }
}

struct EPSectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.black))
                    .foregroundStyle(EPTheme.primary)
                    .frame(width: 24, height: 24)
                    .background(EPTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct EPKPIBox: View {
    let title: String
    let value: String
    let subtitle: String
    var icon: String? = nil
    var tint: Color = EPTheme.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.black))
                        .foregroundStyle(tint)
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.title2.weight(.black))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.14), lineWidth: 1)
        )
    }
}

struct EPStatusPill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = EPTheme.primary

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.black))
            }
            Text(text)
                .font(.caption2.weight(.black))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct EPWebTab: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
}

struct EPWebTabBar: View {
    let tabs: [EPWebTab]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    Button {
                        selected = tab.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.caption.weight(.black))
                            Text(tab.title)
                                .font(.caption.weight(.black))
                        }
                        .foregroundStyle(selected == tab.id ? .white : EPTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selected == tab.id ? EPTheme.primary : Color(.systemGray6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct EPPlaceholderActionButton: View {
    enum Variant {
        case accent
        case white
    }

    let title: String
    let icon: String
    var message: String = "Esta acción queda preparada para conectarla en el siguiente paso."
    var variant: Variant = .accent

    @State private var showAlert = false

    var body: some View {
        Button {
            showAlert = true
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(variant == .white ? .white : EPTheme.primary)
                .background(variant == .white ? .white.opacity(0.25) : EPTheme.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .alert(title, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct ReplicaFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

enum RichTextHTML {
    static func plainText(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        return stripHTML(trimmed)
    }

    static func html(fromPlainText text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !nonEmpty.isEmpty, nonEmpty.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }) {
            let items = nonEmpty.map { line in
                let clean = String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
                return "<li>\(escape(clean))</li>"
            }
            return "<ul>\(items.joined())</ul>"
        }

        return nonEmpty.map { "<p>\(escape($0.trimmingCharacters(in: .whitespaces)))</p>" }.joined()
    }

    static func attributedString(from html: String) -> NSAttributedString? {
        let wrapped = """
        <style>
        body { font-family: -apple-system; font-size: 15px; color: #1f2937; }
        p { margin: 0 0 8px 0; }
        ul, ol { margin: 0 0 8px 18px; padding: 0; }
        li { margin: 0 0 5px 0; }
        strong, b { font-weight: 700; }
        </style>
        \(html)
        """

        guard let data = wrapped.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
    }

    static func blocks(from html: String) -> [RichTextBlock] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</li>", with: "</li>\n", options: [.caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "</p>\n", options: [.caseInsensitive])
            .replacingOccurrences(of: "</div>", with: "</div>\n", options: [.caseInsensitive])

        let pattern = #"(?is)<h([1-6])[^>]*>(.*?)</h\1>|<li[^>]*>(.*?)</li>|<p[^>]*>(.*?)</p>|<div[^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return plainBlocks(from: trimmed)
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: range)
        guard !matches.isEmpty else {
            return plainBlocks(from: trimmed)
        }

        var blocks: [RichTextBlock] = []
        var consumedRanges: [Range<String.Index>] = []

        for match in matches {
            guard let fullRange = Range(match.range, in: normalized) else { continue }
            consumedRanges.append(fullRange)

            if let levelRange = Range(match.range(at: 1), in: normalized),
               let contentRange = Range(match.range(at: 2), in: normalized),
               let level = Int(normalized[levelRange]) {
                let text = inlineAttributed(from: String(normalized[contentRange]))
                if !text.characters.isEmpty {
                    blocks.append(RichTextBlock(kind: .heading(level: level), text: text))
                }
                continue
            }

            if let listRange = Range(match.range(at: 3), in: normalized) {
                let text = inlineAttributed(from: String(normalized[listRange]))
                if !text.characters.isEmpty {
                    blocks.append(RichTextBlock(kind: .bullet, text: text))
                }
                continue
            }

            for group in [4, 5] {
                if let paragraphRange = Range(match.range(at: group), in: normalized) {
                    let text = inlineAttributed(from: String(normalized[paragraphRange]))
                    if !text.characters.isEmpty {
                        blocks.append(RichTextBlock(kind: .paragraph, text: text))
                    }
                }
            }
        }

        if blocks.isEmpty {
            return plainBlocks(from: trimmed)
        }

        let unmatched = unmatchedText(in: normalized, excluding: consumedRanges)
        if !unmatched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(contentsOf: plainBlocks(from: unmatched))
        }

        return blocks
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func plainBlocks(from value: String) -> [RichTextBlock] {
        let plain = stripHTML(value)
        return plain
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("- ") {
                    return RichTextBlock(kind: .bullet, text: inlineAttributed(from: String(line.dropFirst(2))))
                }
                return RichTextBlock(kind: .paragraph, text: inlineAttributed(from: line))
            }
    }

    private static func inlineAttributed(from html: String) -> AttributedString {
        let markdown = html
            .replacingOccurrences(of: "<strong[^>]*>", with: "**", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</strong>", with: "**", options: .caseInsensitive)
            .replacingOccurrences(of: "<b[^>]*>", with: "**", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</b>", with: "**", options: .caseInsensitive)
            .replacingOccurrences(of: "<em[^>]*>", with: "*", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</em>", with: "*", options: .caseInsensitive)
            .replacingOccurrences(of: "<i[^>]*>", with: "*", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</i>", with: "*", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let decoded = decodeEntities(markdown)
        if let attributed = try? AttributedString(markdown: decoded) {
            return attributed
        }
        return AttributedString(decoded)
    }

    private static func unmatchedText(in value: String, excluding ranges: [Range<String.Index>]) -> String {
        var result = ""
        var cursor = value.startIndex

        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if cursor < range.lowerBound {
                result += value[cursor..<range.lowerBound]
            }
            if cursor < range.upperBound {
                cursor = range.upperBound
            }
        }

        if cursor < value.endIndex {
            result += value[cursor..<value.endIndex]
        }

        return result
    }

    private static func stripHTML(_ value: String) -> String {
        decodeEntities(value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</(p|div|li|h[1-6]|section)>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<li[^>]*>", with: "- ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

struct RichTextBlock: Identifiable {
    enum Kind {
        case heading(level: Int)
        case paragraph
        case bullet
    }

    let id = UUID()
    let kind: Kind
    let text: AttributedString
}

struct RichTextRenderer: View {
    let html: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            let blocks = RichTextHTML.blocks(from: html)
            if blocks.isEmpty {
                EmptyView()
            } else {
                ForEach(blocks) { block in
                    switch block.kind {
                    case .heading(let level):
                        Text(block.text)
                            .font(level <= 2 ? .subheadline.weight(.black) : .caption.weight(.black))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .paragraph:
                        Text(block.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    case .bullet:
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(EPTheme.primary)
                                .frame(width: 5, height: 5)
                            Text(block.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RichTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var html: String
    var minHeight: CGFloat = 104

    @State private var plainText = ""
    @State private var isPreview = false
    @State private var isSyncingFromHTML = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.black))
                Spacer()
                Button {
                    isPreview.toggle()
                    if !isPreview {
                        syncPlainTextFromHTML()
                    }
                } label: {
                    Text(isPreview ? "Editar" : "Vista")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(EPTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(EPTheme.primary.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if isPreview {
                RichTextRenderer(html: html.isEmpty ? "<p>\(placeholder)</p>" : html)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                    .padding(10)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                TextEditor(text: $plainText)
                    .font(.subheadline)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(placeholder)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .onAppear {
            syncPlainTextFromHTML()
        }
        .onChange(of: plainText) { _, newValue in
            guard !isSyncingFromHTML else { return }
            html = RichTextHTML.html(fromPlainText: newValue)
        }
    }

    private func syncPlainTextFromHTML() {
        isSyncingFromHTML = true
        plainText = RichTextHTML.plainText(from: html)
        DispatchQueue.main.async {
            isSyncingFromHTML = false
        }
    }
}
