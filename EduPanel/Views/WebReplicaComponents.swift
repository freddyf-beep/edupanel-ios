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
    let title: String
    let icon: String
    var message: String = "Esta acción queda preparada para conectarla en el siguiente paso."

    @State private var showAlert = false

    var body: some View {
        Button {
            showAlert = true
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(EPTheme.primary)
                .background(EPTheme.primary.opacity(0.1), in: Capsule())
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

        if trimmed.range(of: "<[^>]+>", options: .regularExpression) != nil,
           let attributed = attributedString(from: trimmed) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
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

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct RichTextRenderer: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if let attributed = RichTextHTML.attributedString(from: html), html.contains("<") {
            uiView.attributedText = attributed
        } else {
            uiView.text = RichTextHTML.plainText(from: html)
            uiView.font = .preferredFont(forTextStyle: .subheadline)
            uiView.textColor = .secondaryLabel
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 40
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
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
