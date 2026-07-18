import SwiftUI
import UIKit

enum EPTheme {
    static let primary = dynamic(light: "#F03E6E", dark: "#F03E6E")
    static let primaryDark = dynamic(light: "#D6335E", dark: "#D6335E")
    static let primaryLight = dynamic(light: "#FFF0F4", dark: "#30171E")
    static let primaryMid = dynamic(light: "#FDDDE6", dark: "#461C27")
    static let primaryForeground = Color.white
    static let rose = dynamic(light: "#F41F6A", dark: "#F03E6E")
    static let fuchsia = dynamic(light: "#C031D4", dark: "#A855F7")

    static let background = Color(uiColor: .systemGroupedBackground)
    static let ink = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtle = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.22)

    static let statusGreen = dynamic(light: "#22C55E", dark: "#4ADE80")
    static let statusAmber = dynamic(light: "#F59E0B", dark: "#FBBF24")
    static let statusRed = dynamic(light: "#EF4444", dark: "#F87171")
    static let statusBlue = dynamic(light: "#3B82F6", dark: "#60A5FA")

    static let cardRadius: CGFloat = 18
    static let heroRadius: CGFloat = 22
    static let controlRadius: CGFloat = 12
    static let smallRadius: CGFloat = 10
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)

    static let heroGradient = LinearGradient(
        colors: [primary, rose, fuchsia],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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

    private static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: String, fallback: UIColor = .systemPink) -> UIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else { return fallback }

        var value: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&value) else { return fallback }

        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}

struct EPModuleAccent {
    let tint: Color
    let soft: Color
    let gradient: LinearGradient

    init(tint: Color, soft: Color, colors: [Color]) {
        self.tint = tint
        self.soft = soft
        self.gradient = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let primary = EPModuleAccent(
        tint: EPTheme.primary,
        soft: EPTheme.primaryLight,
        colors: [EPTheme.primary, EPTheme.primaryDark, EPTheme.rose]
    )

    static let calificaciones = EPModuleAccent(
        tint: EPTheme.statusGreen,
        soft: EPTheme.color(hex: "#ECFDF5"),
        colors: [EPTheme.color(hex: "#10B981"), EPTheme.color(hex: "#14B8A6"), EPTheme.color(hex: "#06B6D4")]
    )

    static let evaluaciones = EPModuleAccent(
        tint: EPTheme.primary,
        soft: EPTheme.primaryLight,
        colors: [EPTheme.primary, EPTheme.rose, EPTheme.primaryDark]
    )

    static let planificaciones = EPModuleAccent(
        tint: EPTheme.primary,
        soft: EPTheme.primaryLight,
        colors: [EPTheme.primary, EPTheme.primaryDark, EPTheme.color(hex: "#FB7185")]
    )
}

/// Cabecera editorial para las pantallas principales. Mantiene el contenido
/// fuera de superficies translúcidas y reserva el material para los controles.
struct EPPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = EPTheme.primary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EPFocusSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(EPTheme.primary)
                    .frame(width: 44, height: 4)
                    .padding(.top, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.025), radius: 4, y: 1)
    }
}

extension View {
    func epCardSurface(radius: CGFloat = EPTheme.cardRadius) -> some View {
        background(EPTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.025), radius: 4, y: 1)
    }
}

struct EPModuleHeader<Controls: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let icon: String
    let accent: EPModuleAccent
    private let controls: Controls

    @Environment(\.displayMode) private var displayMode

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        accent: EPModuleAccent = .primary,
        @ViewBuilder controls: () -> Controls
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: displayMode.isSimple ? 10 : 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(eyebrow.uppercased(), systemImage: icon)
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(title)
                        .font(.system(size: displayMode.isSimple ? 20 : 23, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    if let subtitle, !subtitle.isEmpty, !displayMode.isSimple {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            }

            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(displayMode.isSimple ? 15 : 18)
        .background(accent.gradient, in: RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EPTheme.heroRadius, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: accent.tint.opacity(0.18), radius: 9, y: 4)
    }
}

extension EPModuleHeader where Controls == EmptyView {
    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        accent: EPModuleAccent = .primary
    ) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, icon: icon, accent: accent) {
            EmptyView()
        }
    }
}

struct EPSectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: displayMode.isSimple ? 10 : 12, weight: .bold))
                    .foregroundStyle(EPTheme.primary)
                    .frame(width: displayMode.isSimple ? 24 : 28, height: displayMode.isSimple ? 24 : 28)
                    .background(EPTheme.primaryLight, in: RoundedRectangle(cornerRadius: EPTheme.smallRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let subtitle, !subtitle.isEmpty, !displayMode.isSimple {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct EPCollapsibleSection<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let icon: String
    private let tint: Color
    private let content: Content
    @State private var expanded: Bool

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color = EPTheme.primary,
        startsExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.content = content()
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        EPWebCard {
            VStack(alignment: .leading, spacing: expanded ? 14 : 0) {
                Button {
                    withAnimation(EPTheme.spring) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 28, height: 28)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: EPTheme.smallRadius, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.primary)
                            if let subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

struct EPKPIBox: View {
    let title: String
    let value: String
    let subtitle: String
    var icon: String? = nil
    var tint: Color = EPTheme.primary

    @Environment(\.displayMode) private var displayMode

    var body: some View {
        VStack(alignment: .leading, spacing: displayMode.isSimple ? 6 : 9) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: displayMode.isSimple ? 10 : 12, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: displayMode.isSimple ? 22 : 28, height: displayMode.isSimple ? 22 : 28)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(value)
                .font(.system(size: displayMode.isSimple ? 20 : 24, weight: .black))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            if !displayMode.isSimple {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: displayMode.isSimple ? 64 : 98, alignment: .topLeading)
        .padding(displayMode.isSimple ? 10 : 13)
        .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EPTheme.cardRadius, style: .continuous)
                .stroke(EPTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 5, y: 1)
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
                    .font(.system(size: 9, weight: .black))
            }
            Text(text)
                .font(.system(size: 11, weight: .black))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 1))
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

    @Namespace private var tabNamespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    let isSelected = selected == tab.id
                    Button {
                        withAnimation(EPTheme.spring) {
                            selected = tab.id
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .black))
                                .symbolEffect(.bounce, value: isSelected)
                            Text(tab.title)
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(isSelected ? EPTheme.primary : EPTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: EPTheme.smallRadius, style: .continuous)
                                    .fill(EPTheme.primaryLight)
                                    .matchedGeometryEffect(id: "ep-tab-selection", in: tabNamespace)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: EPTheme.smallRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(EPTheme.card, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous)
                    .stroke(EPTheme.border, lineWidth: 1)
            )
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct EPEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
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
                        .background(EPTheme.primaryLight, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if isPreview {
                RichTextRenderer(html: html.isEmpty ? "<p>\(placeholder)</p>" : html)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                    .padding(10)
                    .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
            } else {
                TextEditor(text: $plainText)
                    .font(.subheadline)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(EPTheme.subtle, in: RoundedRectangle(cornerRadius: EPTheme.controlRadius, style: .continuous))
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
