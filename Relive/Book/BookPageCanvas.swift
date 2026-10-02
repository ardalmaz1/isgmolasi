import ReliveCore
import SwiftUI
import UIKit

/// Colours and type of a book style. Pages are printed matter: they keep their own paper colour
/// in Dark Mode, like a real book under a lamp.
struct BookTheme {
    var paper: Color
    var ink: Color
    var secondaryInk: Color
    var titleDesign: Font.Design
    var bodyDesign: Font.Design
    var uppercaseTitles: Bool

    static func theme(for style: BookStyle) -> BookTheme {
        switch style {
        case .classic:
            BookTheme(
                paper: Color(red: 0.965, green: 0.945, blue: 0.906),
                ink: Color(red: 0.16, green: 0.14, blue: 0.12),
                secondaryInk: Color(red: 0.5, green: 0.46, blue: 0.41),
                titleDesign: .serif, bodyDesign: .serif, uppercaseTitles: false
            )
        case .editorial:
            BookTheme(
                paper: Color(red: 0.985, green: 0.98, blue: 0.97),
                ink: Color(red: 0.06, green: 0.06, blue: 0.06),
                secondaryInk: Color(red: 0.4, green: 0.39, blue: 0.37),
                titleDesign: .serif, bodyDesign: .default, uppercaseTitles: false
            )
        case .film:
            BookTheme(
                paper: Color(red: 0.075, green: 0.07, blue: 0.065),
                ink: Color(red: 0.93, green: 0.62, blue: 0.27),
                secondaryInk: Color(red: 0.93, green: 0.62, blue: 0.27).opacity(0.65),
                titleDesign: .monospaced, bodyDesign: .monospaced, uppercaseTitles: true
            )
        }
    }
}

/// The words on a page, formatted from its facts.
struct BookPageText {
    var eyebrow: String?
    var title: String?
    var subtitle: String?
    var body: String?
    var footer: String?
    var folio: String?

    @MainActor
    init(page: BookPage) {
        let title = CreationText.title(page.title, use: .headline)
        let place = CreationText.place(page.place)
        switch page.kind {
        case .cover, .closing:
            self.title = title ?? CreationText.periodLine(page.dateSpan)
            subtitle = [title == nil ? nil : CreationText.periodLine(page.dateSpan), place == title ? nil : place]
                .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .tripTitle:
            eyebrow = "A trip"
            self.title = title
            subtitle = [CreationText.dateLine(page.dateSpan), place == title ? nil : place].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .opener:
            let day = CreationText.dayLine(page.dateSpan)
            self.title = CreationText.title(page.title, use: .label) ?? day
            eyebrow = page.title == nil ? nil : day
            subtitle = place == self.title ? nil : place
        case .bookNote:
            body = page.text
        case .momentNote:
            eyebrow = "Your note"
            self.title = CreationText.title(page.title, use: .label)
            body = page.text
        case .photos:
            break
        }
        if page.kind == .opener || page.kind == .photos {
            footer = [CreationText.title(page.runningTitle, use: .label), CreationText.dayLine(page.runningDate)]
                .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            folio = page.folio.map(String.init)
        }
    }

    /// For VoiceOver: what the page shows, in a sentence.
    @MainActor
    static func accessibilityDescription(of page: BookPage, total: Int) -> String {
        let text = BookPageText(page: page)
        var parts: [String] = []
        switch page.kind {
        case .cover: parts.append("Cover")
        case .closing: parts.append("Last page")
        default: parts.append("Page \(page.id + 1) of \(total)")
        }
        parts += [text.eyebrow, text.title, text.subtitle, text.body].compactMap { $0 }
        if !page.slots.isEmpty {
            parts.append(Counted.text(page.slots.count, "photo", "photos"))
        }
        if page.kind == .photos, let footer = text.footer {
            parts.append(footer)
        }
        return parts.joined(separator: ". ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// One book page, drawn at design size (1080 × 1350) for the reader and for export.
struct BookPageCanvas: View {
    static let size = BookLayoutEngine.pageSize

    let page: BookPage
    let style: BookStyle
    let images: CanvasImages
    var missing: Set<AssetID> = []

    private var theme: BookTheme { BookTheme.theme(for: style) }
    private var text: BookPageText { BookPageText(page: page) }
    private var width: CGFloat { Self.size.width }
    private var height: CGFloat { Self.size.height }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.paper

            ForEach(Array(page.slots.enumerated()), id: \.offset) { _, slot in
                photo(slot)
            }

            switch page.kind {
            case .cover: cover
            case .closing: closing
            case .tripTitle: tripTitle
            case .opener: opener
            case .bookNote, .momentNote: notePage
            case .photos: EmptyView()
            }

            if page.kind == .photos || page.kind == .opener {
                footer
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    // MARK: - Photos

    @ViewBuilder
    private func photo(_ slot: BookPhotoSlot) -> some View {
        let canvasPhoto = CanvasPhoto(
            image: images[slot.assetID],
            size: slot.frame.cgSize,
            isMissing: missing.contains(slot.assetID),
            placeholder: style == .film ? Color(white: 0.18) : Color(red: 0.88, green: 0.86, blue: 0.82)
        )
        switch style {
        case .film:
            canvasPhoto
                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 10))
                .placed(at: slot.frame)
        case .classic:
            canvasPhoto
                .shadow(color: .black.opacity(page.template == .fullBleed ? 0 : 0.12), radius: 6, y: 3)
                .placed(at: slot.frame)
        case .editorial:
            canvasPhoto.placed(at: slot.frame)
        }
    }

    // MARK: - Text pages

    private func titleFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: theme.titleDesign)
    }

    private func display(_ string: String) -> String {
        theme.uppercaseTitles ? string.uppercased() : string
    }

    @ViewBuilder
    private var cover: some View {
        if let frame = page.textFrame {
            let overPhoto = style == .editorial && !page.slots.isEmpty
            VStack(alignment: overPhoto ? .leading : .center, spacing: 18) {
                if let title = text.title {
                    Text(display(title))
                        .font(titleFont(style == .editorial ? 128 : 86, weight: style == .editorial ? .semibold : .regular))
                        .foregroundStyle(overPhoto ? Color.white : theme.ink)
                        .multilineTextAlignment(overPhoto ? .leading : .center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.35)
                }
                if let subtitle = text.subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 26, weight: .semibold, design: theme.bodyDesign))
                        .tracking(5)
                        .foregroundStyle(overPhoto ? Color.white.opacity(0.92) : theme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .shadow(color: overPhoto ? .black.opacity(0.35) : .clear, radius: 12)
            .frame(width: frame.width, height: frame.height, alignment: overPhoto ? .topLeading : .center)
            .offset(x: frame.x, y: frame.y)
        }
    }

    private var closing: some View {
        VStack(spacing: 22) {
            if let title = text.title {
                Text(display(title))
                    .font(titleFont(64))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
            }
            if let subtitle = text.subtitle {
                Text(subtitle)
                    .font(.system(size: 28, design: theme.bodyDesign))
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            MadeWithRelive(size: 22, color: theme.secondaryInk.opacity(0.8))
                .padding(.top, 40)
        }
        .frame(width: width - 240, height: height)
        .offset(x: 120)
    }

    private var tripTitle: some View {
        VStack(spacing: 24) {
            if let eyebrow = text.eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 24, weight: .semibold, design: theme.bodyDesign))
                    .tracking(6)
                    .foregroundStyle(theme.secondaryInk)
            }
            if let title = text.title {
                Text(display(title))
                    .font(titleFont(110))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
            }
            if let subtitle = text.subtitle {
                Text(subtitle)
                    .font(.system(size: 30, design: theme.bodyDesign))
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: width - 240, height: height)
        .offset(x: 120)
    }

    @ViewBuilder
    private var opener: some View {
        if let frame = page.textFrame {
            VStack(alignment: .leading, spacing: 12) {
                if let eyebrow = text.eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 22, weight: .semibold, design: theme.bodyDesign))
                        .tracking(4)
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                }
                if let title = text.title {
                    Text(display(title))
                        .font(titleFont(style == .editorial ? 84 : 66, weight: style == .editorial ? .semibold : .regular))
                        .foregroundStyle(theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.4)
                }
                if let subtitle = text.subtitle {
                    Text(subtitle)
                        .font(.system(size: 26, design: theme.bodyDesign))
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(width: frame.width, height: frame.height, alignment: .bottomLeading)
            .offset(x: frame.x, y: frame.y)
        }
    }

    @ViewBuilder
    private var notePage: some View {
        if let frame = page.textFrame, let body = text.body {
            VStack(spacing: 28) {
                if let eyebrow = text.eyebrow {
                    Text(([eyebrow] + [text.title].compactMap { $0 }).joined(separator: " · ").uppercased())
                        .font(.system(size: 22, weight: .semibold, design: theme.bodyDesign))
                        .tracking(4)
                        .foregroundStyle(theme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                Text(body)
                    .font(.system(size: 44, design: style == .film ? .monospaced : .serif).italic())
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(10)
                    .minimumScaleFactor(0.3)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.x, y: frame.y)
        }
    }

    private var footer: some View {
        let margin = width * 0.08
        return HStack {
            Text(text.footer ?? "")
                .lineLimit(1)
            Spacer(minLength: 20)
            Text(text.folio ?? "")
        }
        .font(.system(size: 20, weight: .medium, design: theme.bodyDesign))
        .tracking(1.5)
        .foregroundStyle(page.template == .fullBleed && style == .editorial ? Color.white.opacity(0.85) : theme.secondaryInk)
        .shadow(color: page.template == .fullBleed && style == .editorial ? .black.opacity(0.4) : .clear, radius: 6)
        .frame(width: width - 2 * margin, height: 40)
        .offset(x: margin, y: height - margin * 0.75 - 20)
    }
}
