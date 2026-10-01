import ReliveCore
import SwiftUI
import UIKit

/// The words on one story card, formatted from its facts.
struct StoryCardText: Equatable {
    var title: String?
    var subtitle: String?
    var coordinate: String?
    var stamp: String?
    var closing: String?

    @MainActor
    init(card: StoryCardPlan) {
        switch card.kind {
        case .opening:
            let title = CreationText.title(card.title, use: .headline)
            let period = CreationText.periodLine(card.dateSpan)
            // Without a shared name, the dates are the title.
            self.title = title ?? period
            self.subtitle = title == nil ? nil : period
            self.coordinate = CreationText.coordinate(card.coordinate)
        case .memory:
            title = CreationText.title(card.title, use: .label)
            subtitle = CreationText.dayLine(card.dateSpan)
        case .photo:
            break
        case .closing:
            if case .year(let year)? = card.title {
                closing = "And that’s our \(year)."
            }
        }
        stamp = CreationText.filmStamp(card.captureDate)
    }
}

/// One 9:16 story card, drawn at design size for both preview and export.
struct StoryCardCanvas: View {
    static let size = CreationAspectRatio.story.designSize

    let card: StoryCardPlan
    let style: StoryStyle
    let image: UIImage?
    var isMissing = false
    /// Position among the photo cards, for Editorial's numbering.
    var number: Int = 1
    var showsWatermark = true

    private var text: StoryCardText { StoryCardText(card: card) }
    private var width: CGFloat { Self.size.width }
    private var height: CGFloat { Self.size.height }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch style {
            case .minimal: minimal
            case .film: film
            case .travel: travel
            case .romantic: romantic
            case .editorial: editorial
            }
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

    private var watermarkColor: Color {
        switch style {
        case .minimal: Self.minimalInk.opacity(0.45)
        case .romantic: Self.romanticInk.opacity(0.5)
        case .film: Self.filmAmber.opacity(0.6)
        case .travel, .editorial: card.kind == .closing ? Color.black.opacity(0.4) : Color.white.opacity(0.7)
        }
    }

    private func photo(_ size: CGSize) -> CanvasPhoto {
        CanvasPhoto(image: image, size: size, isMissing: isMissing)
    }

    /// Natural-shape box for a photo inside a maximum box.
    private func naturalSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let aspect = min(1.5, max(0.6, image.map { $0.size.width / max($0.size.height, 1) } ?? 0.75))
        var size = CGSize(width: maxWidth, height: maxWidth / aspect)
        if size.height > maxHeight {
            size = CGSize(width: maxHeight * aspect, height: maxHeight)
        }
        return size
    }

    // MARK: - Minimal

    static let minimalPaper = Color(red: 0.961, green: 0.949, blue: 0.925)
    static let minimalInk = Color(red: 0.14, green: 0.125, blue: 0.11)

    @ViewBuilder
    private var minimal: some View {
        Self.minimalPaper
        switch card.kind {
        case .opening, .memory:
            photo(CGSize(width: 900, height: 1125)).offset(x: 90, y: 210)
            VStack(alignment: .leading, spacing: 14) {
                if let title = text.title {
                    Text(title)
                        .font(.system(size: card.kind == .opening ? 76 : 58, design: .serif))
                        .foregroundStyle(Self.minimalInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                }
                if let subtitle = text.subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 26, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(Self.minimalInk.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 900, alignment: .leading)
            .offset(x: 90, y: 1395)
        case .photo:
            let size = naturalSize(maxWidth: 900, maxHeight: 1420)
            photo(size).offset(x: (width - size.width) / 2, y: (height - size.height) / 2 - 30)
        case .closing:
            closingText(color: Self.minimalInk, font: .system(size: 64, design: .serif).italic())
        }
    }

    // MARK: - Film

    static let filmBlack = Color(red: 0.055, green: 0.05, blue: 0.047)
    static let filmAmber = Color(red: 0.93, green: 0.6, blue: 0.22)

    @ViewBuilder
    private var film: some View {
        Self.filmBlack
        if card.kind == .closing {
            closingText(color: Self.filmAmber, font: .system(size: 46, weight: .medium, design: .monospaced))
        } else {
            let frame = CGRect(x: 150, y: 300, width: 780, height: 1170)
            let unit = frame.width
            ZStack(alignment: .topLeading) {
                Color(red: 0.13, green: 0.12, blue: 0.11)
                SprocketHoles(isVertical: true, unit: unit).fill(Self.filmBlack)
            }
            .frame(width: unit * 1.34, height: height)
            .offset(x: frame.minX - unit * 0.17)
            photo(frame.size).offset(x: frame.minX, y: frame.minY)
            if let stamp = text.stamp {
                Text(stamp)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                    .shadow(color: Color(red: 1, green: 0.4, blue: 0.1).opacity(0.6), radius: 6)
                    .frame(width: frame.width - 40, alignment: .trailing)
                    .offset(x: frame.minX + 20, y: frame.maxY - 70)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let title = text.title {
                    Text(title.uppercased())
                        .font(.system(size: card.kind == .opening ? 50 : 40, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Self.filmAmber)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                }
                if let subtitle = text.subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 26, weight: .medium, design: .monospaced))
                        .foregroundStyle(Self.filmAmber.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: frame.width, alignment: .leading)
            .offset(x: frame.minX, y: frame.maxY + 50)
        }
    }

    // MARK: - Travel

    @ViewBuilder
    private var travel: some View {
        if card.kind == .closing {
            Color(red: 0.07, green: 0.07, blue: 0.08)
            closingText(color: .white, font: .system(size: 72, weight: .heavy).width(.condensed))
        } else {
            photo(CGSize(width: width, height: height))
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
                .frame(width: width, height: 800)
                .offset(y: height - 800)
            VStack(alignment: .leading, spacing: 14) {
                if let coordinate = text.coordinate, card.kind == .opening {
                    Text(coordinate)
                        .font(.system(size: 26, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let title = text.title {
                    Text(title.uppercased())
                        .font(.system(size: card.kind == .opening ? 136 : 88, weight: .heavy).width(.condensed))
                        .tracking(card.kind == .opening ? 6 : 3)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.35)
                }
                if let subtitle = text.subtitle ?? (card.kind == .photo ? CreationText.dayLine(card.captureDate.map { DateSpan(start: $0, end: $0) }) : nil) {
                    Text(subtitle.uppercased())
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 10)
            .frame(width: width - 160, height: 560, alignment: .bottomLeading)
            .offset(x: 80, y: height - 560 - 170)
        }
    }

    // MARK: - Romantic

    static let romanticPaper = Color(red: 0.95, green: 0.9, blue: 0.875)
    static let romanticInk = Color(red: 0.36, green: 0.23, blue: 0.2)

    @ViewBuilder
    private var romantic: some View {
        Self.romanticPaper
        switch card.kind {
        case .closing:
            closingText(color: Self.romanticInk, font: .system(size: 68, design: .serif).italic())
        default:
            let size = card.kind == .photo ? naturalSize(maxWidth: 840, maxHeight: 1300) : CGSize(width: 820, height: 1025)
            let top: CGFloat = card.kind == .photo ? (height - size.height) / 2 - 40 : 250
            photo(size)
                .padding(18)
                .background(Color.white)
                .shadow(color: Self.romanticInk.opacity(0.18), radius: 24, y: 10)
                .rotationEffect(.degrees(card.kind == .opening ? -1.5 : (card.kind == .memory ? 1.2 : 0)))
                .offset(x: (width - size.width) / 2 - 18, y: top - 18)
            if card.kind != .photo {
                VStack(spacing: 14) {
                    if let title = text.title {
                        Text(title)
                            .font(.system(size: card.kind == .opening ? 74 : 58, design: .serif).italic())
                            .foregroundStyle(Self.romanticInk)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                    }
                    if let subtitle = text.subtitle {
                        Text(subtitle)
                            .font(.system(size: 30, design: .serif).italic())
                            .foregroundStyle(Self.romanticInk.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(width: 900)
                .offset(x: 90, y: 1340)
            }
        }
    }

    // MARK: - Editorial

    @ViewBuilder
    private var editorial: some View {
        if card.kind == .closing {
            Color(red: 0.97, green: 0.96, blue: 0.94)
            closingText(color: .black, font: .system(size: 76, weight: .semibold, design: .serif))
        } else {
            photo(CGSize(width: width, height: height))
            if card.kind == .photo {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: width - 72, height: height - 72)
                    .offset(x: 36, y: 36)
            } else {
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 760)
                VStack(alignment: .leading, spacing: 16) {
                    if card.kind == .memory {
                        Text(String(format: "%02d", number))
                            .font(.system(size: 120, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                    }
                    if let title = text.title {
                        Text(title)
                            .font(.system(size: card.kind == .opening ? 150 : 72, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.35)
                    }
                    if let subtitle = text.subtitle {
                        Text(subtitle.uppercased())
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(6)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 10)
                .frame(width: width - 160, alignment: .leading)
                .offset(x: 80, y: 130)
            }
        }
    }

    // MARK: - Closing

    private func closingText(color: Color, font: Font) -> some View {
        Text(text.closing ?? "")
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .frame(width: width - 200, height: height)
            .offset(x: 100)
    }
}
