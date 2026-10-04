import ReliveCore
import SwiftUI
import UIKit

/// The words on one story card, formatted from its facts and the user's show/hide choices.
/// Every line is nil when there is nothing true to say.
struct StoryCardText: Equatable {
    var title: String?
    var subtitle: String?
    var meta: String?
    var coordinate: String?
    var stamp: String?

    @MainActor
    init(card: StoryCard) {
        let place = card.showsPlace ? CreationText.place(card.place) : nil
        let day = card.showsDate ? CreationText.dayLine(card.dateSpan) : nil
        coordinate = card.showsCoordinates ? CreationText.coordinate(card.coordinate) : nil
        // A camera-style imprint only for photos taken on one known day.
        if card.showsDate, let span = card.dateSpan, Calendar.current.isDate(span.start, inSameDayAs: span.end) {
            stamp = CreationText.filmStamp(span.start)
        }

        switch card.role {
        case .opening:
            var headline = CreationText.title(card.title, use: .headline)
            // A moment or trip with a real place opens with the place: "KAŞ / August 2026".
            if case .named? = card.title, let place { headline = place }
            let period = card.showsDate ? CreationText.periodLine(card.dateSpan) : nil
            if let headline {
                title = headline
                subtitle = period
            } else if let span = card.dateSpan, card.showsDate, Calendar.current.isDate(span.start, inSameDayAs: span.end) {
                title = CreationText.dateLine(span)
            } else {
                // Several years, or nothing known: a neutral headline, never an invented one.
                title = "Our Memories"
                subtitle = period
            }
            if let place, place != title { meta = place }
        case .photo:
            meta = [place, day].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .place:
            title = place ?? day
            subtitle = title == day ? nil : (card.showsDate ? CreationText.dateLine(card.dateSpan) : nil)
        case .closing:
            if let year = card.closingYear {
                title = "And that’s our \(year)."
            } else {
                title = [place, card.showsDate ? CreationText.periodLine(card.dateSpan) : nil].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
            }
        }
    }

    /// For VoiceOver: what the card shows.
    @MainActor
    static func accessibilityDescription(of card: StoryCard, number: Int, total: Int) -> String {
        let text = StoryCardText(card: card)
        let kind: String
        switch card.role {
        case .opening: kind = "Opening card"
        case .photo: kind = card.photos.count == 1 ? "Photo card" : "Card with \(card.photos.count) photos"
        case .place: kind = "Place card"
        case .closing: kind = "Closing card"
        }
        return (["\(kind), \(number) of \(total)", text.title, text.subtitle, text.meta, text.coordinate].compactMap { $0 }).joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Geometry

/// Where a card's photos go, in design points (1080 × 1920). Shared by preview and export, so
/// the export loads each photo at the size of its frame and draws exactly what was previewed.
struct StorySlot: Equatable {
    var frame: CGRect
    var rotation: Double = 0
}

enum StoryCardGeometry {
    static let size = CreationAspectRatio.story.designSize
    static var width: CGFloat { size.width }
    static var height: CGFloat { size.height }

    /// A box of `aspect` (width / height) fitted inside `maxWidth` × `maxHeight`.
    static func fitted(aspect: Double, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let aspect = CGFloat(min(2.4, max(0.5, aspect)))
        var size = CGSize(width: maxWidth, height: maxWidth / aspect)
        if size.height > maxHeight { size = CGSize(width: maxHeight * aspect, height: maxHeight) }
        return size
    }

    static func centered(_ size: CGSize, y: CGFloat? = nil) -> CGRect {
        CGRect(x: (width - size.width) / 2, y: y ?? (height - size.height) / 2, width: size.width, height: size.height)
    }

    static func slots(for card: StoryCard, style: StoryStyle, aspects: [Double]) -> [StorySlot] {
        let a = aspects + Array(repeating: 0.75, count: max(0, card.photos.count - aspects.count))
        let w = width, h = height
        switch card.layout {
        case .caption, .closing:
            return []

        case .cover:
            switch style {
            case .minimal: return [StorySlot(frame: CGRect(x: 90, y: 210, width: 900, height: 1125))]
            case .film: return [StorySlot(frame: CGRect(x: 150, y: 300, width: 780, height: 1170))]
            case .travel, .editorial: return [StorySlot(frame: CGRect(x: 0, y: 0, width: w, height: h))]
            case .romantic: return [StorySlot(frame: CGRect(x: 130, y: 250, width: 820, height: 1025), rotation: -1.5)]
            }

        case .coverFramed:
            switch style {
            case .minimal: return [StorySlot(frame: centered(fitted(aspect: a[0], maxWidth: 640, maxHeight: 820), y: 760))]
            case .film: return [StorySlot(frame: CGRect(x: 240, y: 720, width: 600, height: 900))]
            case .travel: return [StorySlot(frame: CGRect(x: 0, y: 980, width: w, height: 940))]
            case .romantic: return [StorySlot(frame: CGRect(x: 230, y: 760, width: 620, height: 775), rotation: 1.2)]
            case .editorial: return [StorySlot(frame: CGRect(x: 260, y: 820, width: 760, height: 1010))]
            }

        case .fullBleed:
            switch style {
            case .minimal: return [StorySlot(frame: CGRect(x: 0, y: 0, width: w, height: h - 300))]
            case .film: return [StorySlot(frame: CGRect(x: 120, y: 120, width: w - 240, height: h - 300))]
            case .travel, .editorial: return [StorySlot(frame: CGRect(x: 0, y: 0, width: w, height: h))]
            case .romantic: return [StorySlot(frame: centered(CGSize(width: 900, height: 1400), y: 180), rotation: 0.8)]
            }

        case .framed:
            switch style {
            case .minimal, .romantic:
                let size = fitted(aspect: a[0], maxWidth: style == .minimal ? 900 : 840, maxHeight: 1320)
                return [StorySlot(frame: centered(size, y: (h - size.height) / 2 - 60))]
            case .film:
                let size = fitted(aspect: a[0], maxWidth: 780, maxHeight: 1300)
                return [StorySlot(frame: centered(size, y: (h - size.height) / 2 - 40))]
            case .travel:
                let size = fitted(aspect: a[0], maxWidth: w, maxHeight: 1250)
                return [StorySlot(frame: centered(size, y: 330))]
            case .editorial:
                let size = fitted(aspect: a[0], maxWidth: 860, maxHeight: 1300)
                return [StorySlot(frame: CGRect(x: 90, y: 300, width: size.width, height: size.height))]
            }

        case .postcard:
            let size = fitted(aspect: a[0], maxWidth: w - 180, maxHeight: 900)
            return [StorySlot(frame: centered(size, y: 200), rotation: style == .romantic ? -1 : 0)]

        case .duo:
            let stacked = a.prefix(2).allSatisfy { $0 > 1.05 }
            if style == .travel {
                // Split screen, edge to edge.
                return stacked
                    ? [StorySlot(frame: CGRect(x: 0, y: 0, width: w, height: h / 2 - 4)), StorySlot(frame: CGRect(x: 0, y: h / 2 + 4, width: w, height: h / 2 - 4))]
                    : [StorySlot(frame: CGRect(x: 0, y: 0, width: w / 2 - 4, height: h)), StorySlot(frame: CGRect(x: w / 2 + 4, y: 0, width: w / 2 - 4, height: h))]
            }
            let margin: CGFloat = style == .minimal ? 110 : 90
            if stacked {
                let size0 = fitted(aspect: a[0], maxWidth: w - 2 * margin, maxHeight: 700)
                let size1 = fitted(aspect: a[1], maxWidth: w - 2 * margin, maxHeight: 700)
                let gap: CGFloat = style == .film ? 40 : 60
                let top = (h - size0.height - size1.height - gap) / 2 - 40
                return [
                    StorySlot(frame: centered(size0, y: top), rotation: style == .romantic ? -1.2 : 0),
                    StorySlot(frame: centered(size1, y: top + size0.height + gap), rotation: style == .romantic ? 1.0 : 0),
                ]
            }
            let column = (w - 2 * margin - 40) / 2
            let size0 = fitted(aspect: a[0], maxWidth: column, maxHeight: 1100)
            let size1 = fitted(aspect: a[1], maxWidth: column, maxHeight: 1100)
            let top = (h - max(size0.height, size1.height)) / 2 - 40
            return [
                StorySlot(frame: CGRect(x: margin, y: top, width: size0.width, height: size0.height), rotation: style == .romantic ? -1.5 : 0),
                StorySlot(frame: CGRect(x: w - margin - size1.width, y: top + (style == .editorial ? 160 : 0), width: size1.width, height: size1.height), rotation: style == .romantic ? 1.5 : 0),
            ]

        case .duoOffset:
            let big = fitted(aspect: a[0], maxWidth: 760, maxHeight: 1080)
            let small = fitted(aspect: a[1], maxWidth: 520, maxHeight: 700)
            if style == .travel {
                return [
                    StorySlot(frame: CGRect(x: 0, y: 0, width: w, height: 1220)),
                    StorySlot(frame: CGRect(x: w - 80 - small.width, y: 1220 - small.height * 0.45, width: small.width, height: small.height)),
                ]
            }
            return [
                StorySlot(frame: CGRect(x: 70, y: 240, width: big.width, height: big.height), rotation: style == .romantic ? -1.2 : 0),
                StorySlot(frame: CGRect(x: w - 70 - small.width, y: 240 + big.height - small.height * 0.4, width: small.width, height: small.height), rotation: style == .romantic ? 2 : 0),
            ]

        case .trio:
            let margin: CGFloat = style == .travel ? 0 : 80
            let gap: CGFloat = style == .travel ? 8 : 24
            let topHeight: CGFloat = style == .travel ? 1060 : 860
            let top = CGRect(x: margin, y: style == .travel ? 0 : 200, width: w - 2 * margin, height: topHeight)
            let half = (w - 2 * margin - gap) / 2
            let lowerY = top.maxY + gap
            let lowerHeight: CGFloat = style == .travel ? h - lowerY : 620
            return [
                StorySlot(frame: top),
                StorySlot(frame: CGRect(x: margin, y: lowerY, width: half, height: lowerHeight)),
                StorySlot(frame: CGRect(x: margin + half + gap, y: lowerY, width: half, height: lowerHeight)),
            ]

        case .trioStrip:
            let stripX: CGFloat = 200
            let gap: CGFloat = 30
            let frameHeight = (h - 420 - 2 * gap) / 3
            return (0..<3).map { index in
                StorySlot(frame: CGRect(x: stripX, y: 170 + CGFloat(index) * (frameHeight + gap), width: w - 2 * stripX, height: frameHeight))
            }
        }
    }
}

// MARK: - Theme

/// Each style's design system: paper, ink, type and how photos are treated.
struct StoryTheme {
    var background: Color
    var ink: Color
    var secondaryInk: Color
    var titleDesign: Font.Design
    var titleWeight: Font.Weight
    var titleWidth: Font.Width = .standard
    var italicTitles = false
    var uppercaseTitles = false
    var metaDesign: Font.Design = .default

    static func theme(for style: StoryStyle) -> StoryTheme {
        switch style {
        case .minimal:
            StoryTheme(
                background: Color(red: 0.961, green: 0.949, blue: 0.925), ink: Color(red: 0.14, green: 0.125, blue: 0.11),
                secondaryInk: Color(red: 0.14, green: 0.125, blue: 0.11).opacity(0.6), titleDesign: .serif, titleWeight: .regular
            )
        case .film:
            StoryTheme(
                background: Color(red: 0.055, green: 0.05, blue: 0.047), ink: Color(red: 0.93, green: 0.6, blue: 0.22),
                secondaryInk: Color(red: 0.93, green: 0.6, blue: 0.22).opacity(0.7), titleDesign: .monospaced, titleWeight: .semibold,
                uppercaseTitles: true, metaDesign: .monospaced
            )
        case .travel:
            StoryTheme(
                background: Color(red: 0.07, green: 0.07, blue: 0.08), ink: .white, secondaryInk: .white.opacity(0.85),
                titleDesign: .default, titleWeight: .heavy, titleWidth: .condensed, uppercaseTitles: true
            )
        case .romantic:
            StoryTheme(
                background: Color(red: 0.95, green: 0.9, blue: 0.875), ink: Color(red: 0.36, green: 0.23, blue: 0.2),
                secondaryInk: Color(red: 0.36, green: 0.23, blue: 0.2).opacity(0.72), titleDesign: .serif, titleWeight: .regular,
                italicTitles: true, metaDesign: .serif
            )
        case .editorial:
            StoryTheme(
                background: Color(red: 0.97, green: 0.96, blue: 0.94), ink: .black, secondaryInk: .black.opacity(0.62),
                titleDesign: .serif, titleWeight: .semibold
            )
        }
    }

    func title(_ size: CGFloat) -> Font {
        let font = Font.system(size: size, weight: titleWeight, design: titleDesign).width(titleWidth)
        return italicTitles ? font.italic() : font
    }

    func meta(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let font = Font.system(size: size, weight: weight, design: metaDesign)
        return italicTitles ? font.italic() : font
    }

    func display(_ text: String) -> String { uppercaseTitles ? text.uppercased() : text }
}

// MARK: - Canvas

/// One 9:16 story card, drawn at design size for both preview and export. Each style is its own
/// design: Minimal (breathing room), Film (frames, sprockets, date stamps), Travel (place-forward,
/// edge to edge), Romantic (soft prints) and Editorial (large type, asymmetry).
struct StoryCardCanvas: View {
    static let size = StoryCardGeometry.size

    let card: StoryCard
    let style: StoryStyle
    let images: CanvasImages
    var missing: Set<AssetID> = []
    /// Shapes of the card's photos, so the preview and export agree on the arrangement.
    var aspects: [Double] = []
    /// Position among the cards, for Editorial's numbering.
    var number: Int = 1
    var showsWatermark = true

    private var text: StoryCardText { StoryCardText(card: card) }
    private var theme: StoryTheme { StoryTheme.theme(for: style) }
    private var width: CGFloat { Self.size.width }
    private var height: CGFloat { Self.size.height }
    private var slots: [StorySlot] { StoryCardGeometry.slots(for: card, style: style, aspects: aspects) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            decorations
            ForEach(Array(zip(card.photos, slots).enumerated()), id: \.offset) { index, pair in
                photo(pair.0, slot: pair.1, index: index)
            }
            overlays
            words
            if showsWatermark {
                MadeWithRelive(size: 22, color: watermarkColor)
                    .frame(width: width, height: 60)
                    .offset(y: height - 96)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    private var isTextCard: Bool { card.photos.isEmpty }

    private var watermarkColor: Color {
        switch style {
        case .travel: isTextCard || !photoUnderFooter ? Color.white.opacity(0.55) : Color.white.opacity(0.75)
        case .editorial: photoUnderFooter ? Color.white.opacity(0.75) : theme.secondaryInk.opacity(0.7)
        default: theme.secondaryInk.opacity(0.7)
        }
    }

    /// Whether a photo covers the bottom edge (where the watermark sits).
    private var photoUnderFooter: Bool {
        slots.contains { $0.frame.maxY >= height - 40 }
    }

    // MARK: Background and decorations

    @ViewBuilder
    private var background: some View {
        switch style {
        case .travel where !isTextCard && card.layout != .framed && card.layout != .coverFramed && card.layout != .postcard:
            Color.black
        default:
            theme.background
        }
    }

    @ViewBuilder
    private var decorations: some View {
        if style == .film, !isTextCard {
            // A film strip behind the frames: sprocket holes along both edges.
            let unit: CGFloat = 780
            let strip = CGRect(x: 60, y: 0, width: width - 120, height: height)
            ZStack(alignment: .topLeading) {
                Color(red: 0.13, green: 0.12, blue: 0.11)
                SprocketHoles(isVertical: true, unit: unit).fill(Self.filmBlack)
            }
            .frame(width: strip.width, height: strip.height)
            .offset(x: strip.minX)
        }
    }

    static let filmBlack = Color(red: 0.055, green: 0.05, blue: 0.047)

    // MARK: Photos

    @ViewBuilder
    private func photo(_ id: AssetID, slot: StorySlot, index: Int) -> some View {
        let base = CanvasPhoto(image: images[id], size: slot.frame.size, isMissing: missing.contains(id))
        switch style {
        case .minimal:
            base.placed(at: slot.frame)
        case .film:
            ZStack(alignment: .bottomTrailing) {
                base
                if index == 0, let stamp = text.stamp, card.role != .opening {
                    Text(stamp)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                        .shadow(color: Color(red: 1, green: 0.4, blue: 0.1).opacity(0.6), radius: 6)
                        .padding(28)
                }
            }
            .frame(width: slot.frame.width, height: slot.frame.height)
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 10))
            .placed(at: slot.frame)
        case .travel:
            base
                .overlay {
                    if card.layout == .duoOffset && index == 1 {
                        Rectangle().strokeBorder(Color.white, lineWidth: 10)
                    }
                }
                .placed(at: slot.frame)
        case .romantic:
            base
                .padding(18)
                .background(Color.white)
                .shadow(color: theme.ink.opacity(0.18), radius: 24, y: 10)
                .rotationEffect(.degrees(slot.rotation))
                .frame(width: slot.frame.width + 36, height: slot.frame.height + 36)
                .offset(x: slot.frame.minX - 18, y: slot.frame.minY - 18)
        case .editorial:
            base
                .overlay {
                    if card.layout == .fullBleed {
                        Rectangle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3).padding(36)
                    } else if card.layout == .duoOffset && index == 1 {
                        Rectangle().strokeBorder(theme.background, lineWidth: 14)
                    }
                }
                .placed(at: slot.frame)
        }
    }

    /// Gradients that keep white type readable over full-bleed photos.
    @ViewBuilder
    private var overlays: some View {
        if wordsOverPhoto {
            switch textPosition {
            case .top:
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 760)
            case .bottom:
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 820)
                    .offset(y: height - 820)
            }
        }
    }

    // MARK: Words

    private enum TextPosition { case top, bottom }

    /// Travel and Editorial set their words over the photo on edge-to-edge cards.
    private var wordsOverPhoto: Bool {
        guard !isTextCard else { return false }
        switch (style, card.layout) {
        case (.travel, .cover), (.travel, .fullBleed), (.travel, .duo), (.travel, .trio), (.travel, .duoOffset): return hasWords
        case (.editorial, .cover), (.editorial, .fullBleed): return hasWords
        default: return false
        }
    }

    private var textPosition: TextPosition {
        style == .editorial && card.layout == .cover ? .top : .bottom
    }

    private var hasWords: Bool {
        text.title != nil || text.subtitle != nil || text.meta != nil || text.coordinate != nil
    }

    private var inkOnCard: Color { wordsOverPhoto ? .white : theme.ink }
    private var secondaryOnCard: Color { wordsOverPhoto ? .white.opacity(0.9) : theme.secondaryInk }

    @ViewBuilder
    private var words: some View {
        switch card.role {
        case .opening: openingWords
        case .photo: photoWords
        case .place: placeWords
        case .closing: closingWords
        }
    }

    @ViewBuilder
    private var openingWords: some View {
        let framed = card.layout == .coverFramed
        let block = VStack(alignment: alignment, spacing: 14) {
            if let coordinate = text.coordinate {
                Text(coordinate)
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryOnCard)
            }
            if let title = text.title {
                Text(theme.display(title))
                    .font(theme.title(openingTitleSize))
                    .tracking(style == .travel ? 6 : 0)
                    .foregroundStyle(inkOnCard)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
            }
            if let subtitle = text.subtitle {
                Text(subtitle.uppercased())
                    .font(theme.meta(26, weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(secondaryOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let meta = text.meta {
                Text(meta)
                    .font(theme.meta(28))
                    .foregroundStyle(secondaryOnCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .shadow(color: wordsOverPhoto ? .black.opacity(0.3) : .clear, radius: 10)

        switch (style, framed) {
        case (.travel, false), (.editorial, false):
            block
                .frame(width: width - 160, height: 620, alignment: textPosition == .top ? .topLeading : .bottomLeading)
                .offset(x: 80, y: textPosition == .top ? 130 : height - 620 - 190)
        case (.romantic, false):
            block.frame(width: 900).offset(x: 90, y: 1350)
        case (_, false):
            block.frame(width: style == .film ? 780 : 900, alignment: .leading)
                .offset(x: style == .film ? 150 : 90, y: style == .film ? 1520 : 1395)
        case (.editorial, true):
            block.frame(width: width - 160, alignment: .leading).offset(x: 80, y: 220)
        case (_, true):
            block.frame(width: width - 180, alignment: style == .romantic ? .center : .leading)
                .offset(x: 90, y: style == .travel ? 300 : 250)
        }
    }

    private var openingTitleSize: CGFloat {
        switch style {
        case .travel: 136
        case .editorial: card.layout == .coverFramed ? 170 : 150
        case .film: 52
        case .romantic: 76
        case .minimal: card.layout == .coverFramed ? 96 : 76
        }
    }

    private var alignment: HorizontalAlignment { style == .romantic ? .center : .leading }
    private var textAlignment: TextAlignment { style == .romantic ? .center : .leading }

    @ViewBuilder
    private var photoWords: some View {
        switch card.layout {
        case .postcard:
            postcardWords
        default:
            if let meta = text.meta ?? text.coordinate {
                metaLine(meta)
            }
            if style == .editorial, card.layout == .fullBleed || card.layout == .duoOffset || card.layout == .trio {
                Text(String(format: "%02d", number))
                    .font(.system(size: 96, weight: .regular, design: .serif))
                    .foregroundStyle(card.layout == .fullBleed ? .white : theme.ink)
                    .shadow(color: card.layout == .fullBleed ? .black.opacity(0.3) : .clear, radius: 8)
                    .frame(width: width - 160, alignment: .trailing)
                    .offset(x: 80, y: card.layout == .fullBleed ? 90 : 80)
            }
        }
    }

    /// One quiet line of facts under (or over) the photos.
    private func metaLine(_ meta: String) -> some View {
        let lowest = slots.map { $0.frame.maxY }.max() ?? height / 2
        let overPhoto = wordsOverPhoto
        let y = overPhoto ? height - 300 : min(height - 200, lowest + (style == .romantic ? 70 : 50))
        return Text(style == .travel || style == .film ? meta.uppercased() : meta)
            .font(style == .travel ? theme.title(54) : theme.meta(30, weight: style == .film ? .medium : .regular))
            .tracking(style == .travel ? 3 : (style == .minimal ? 2 : 0))
            .foregroundStyle(overPhoto ? .white : theme.secondaryInk)
            .shadow(color: overPhoto ? .black.opacity(0.35) : .clear, radius: 8)
            .multilineTextAlignment(textAlignment)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(width: width - 180, alignment: style == .romantic ? .center : .leading)
            .offset(x: 90, y: y)
    }

    private var postcardWords: some View {
        let lowest = slots.first?.frame.maxY ?? 1100
        let parts = (text.meta ?? "").components(separatedBy: " · ")
        let headline = parts.first ?? ""
        let detail = parts.dropFirst().joined(separator: " · ")
        return VStack(alignment: alignment, spacing: 18) {
            if !headline.isEmpty {
                Text(theme.display(headline))
                    .font(theme.title(style == .travel ? 150 : 104))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
            }
            if !detail.isEmpty {
                Text(detail.uppercased())
                    .font(theme.meta(30, weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(theme.secondaryInk)
            }
            if let coordinate = text.coordinate {
                Text(coordinate)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryInk)
            }
        }
        .frame(width: width - 180, alignment: style == .romantic ? .center : .leading)
        .offset(x: 90, y: lowest + 90)
    }

    private var placeWords: some View {
        VStack(alignment: alignment, spacing: 22) {
            if let title = text.title {
                Text(theme.display(title))
                    .font(theme.title(style == .travel ? 170 : 120))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(3)
                    .minimumScaleFactor(0.3)
            }
            if let subtitle = text.subtitle {
                Text(subtitle.uppercased())
                    .font(theme.meta(30, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(theme.secondaryInk)
            }
            if let coordinate = text.coordinate {
                Text(coordinate)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryInk)
            }
        }
        .frame(width: width - 200, height: height, alignment: style == .editorial ? .bottomLeading : (style == .romantic ? .center : .leading))
        .padding(.bottom, style == .editorial ? 260 : 0)
        .offset(x: 100)
    }

    private var closingWords: some View {
        Text(text.title ?? "")
            .font(style == .film ? theme.title(46) : theme.title(style == .travel ? 72 : 64))
            .foregroundStyle(theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .frame(width: width - 200, height: height)
            .offset(x: 100)
    }
}

private extension View {
    func placed(at rect: CGRect, rotation: Double = 0) -> some View {
        frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .rotationEffect(.degrees(rotation))
            .offset(x: rect.minX, y: rect.minY)
    }
}
