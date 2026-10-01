import ReliveCore
import SwiftUI
import UIKit

/// Colors of a collage style. Creations are images, so they don't follow Dark Mode — they look
/// the same wherever they are shared.
struct CollageTheme {
    var background: Color
    var ink: Color
    var secondaryInk: Color
    var print: Color = .white

    static func theme(for style: CollageStyle) -> CollageTheme {
        switch style {
        case .minimal:
            CollageTheme(background: Color(red: 0.969, green: 0.957, blue: 0.937), ink: Color(red: 0.14, green: 0.125, blue: 0.11), secondaryInk: Color(red: 0.42, green: 0.39, blue: 0.36))
        case .editorial:
            CollageTheme(background: Color(red: 0.98, green: 0.976, blue: 0.965), ink: Color(red: 0.08, green: 0.075, blue: 0.07), secondaryInk: Color(red: 0.38, green: 0.36, blue: 0.33))
        case .grid:
            CollageTheme(background: .white, ink: Color(red: 0.12, green: 0.11, blue: 0.1), secondaryInk: Color(red: 0.45, green: 0.43, blue: 0.4))
        case .film:
            CollageTheme(background: Color(red: 0.07, green: 0.065, blue: 0.06), ink: Color(red: 0.93, green: 0.6, blue: 0.22), secondaryInk: Color(red: 0.93, green: 0.6, blue: 0.22).opacity(0.7))
        case .polaroid:
            CollageTheme(background: Color(red: 0.91, green: 0.89, blue: 0.85), ink: Color(red: 0.2, green: 0.18, blue: 0.16), secondaryInk: Color(red: 0.44, green: 0.41, blue: 0.37), print: Color(red: 0.992, green: 0.988, blue: 0.976))
        case .scrapbook:
            CollageTheme(background: Color(red: 0.88, green: 0.83, blue: 0.74), ink: Color(red: 0.2, green: 0.17, blue: 0.14), secondaryInk: Color(red: 0.42, green: 0.37, blue: 0.31), print: Color(red: 0.995, green: 0.99, blue: 0.98))
        }
    }
}

/// The words on a creation, already formatted from real facts.
struct CaptionContent: Equatable {
    var title: String?
    /// Date and/or place.
    var detail: String?

    var isEmpty: Bool { title == nil && detail == nil }
}

/// A collage, drawn at design size. Used for both the live preview and the export.
struct CollageCanvas: View {
    let layout: CollageLayout
    /// Photos in collage order; `layout` refers to them by index.
    let photoIDs: [AssetID]
    let images: CanvasImages
    var missing: Set<AssetID> = []
    var caption = CaptionContent()
    /// Preview only: outlines the photo selected for swapping.
    var highlightedIndex: Int?
    var showsWatermark = true

    private var theme: CollageTheme { CollageTheme.theme(for: layout.style) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.background

            ForEach(Array(layout.filmStrips.enumerated()), id: \.offset) { _, strip in
                filmStrip(strip)
            }

            ForEach(Array(layout.slots.enumerated()), id: \.offset) { _, slot in
                slotView(slot)
            }

            if let rect = layout.caption, !caption.isEmpty {
                captionView(in: rect)
            }

            if showsWatermark {
                MadeWithRelive(size: CGFloat(max(13, min(20, layout.margin * 0.42))), color: theme.secondaryInk.opacity(0.6))
                    .frame(width: layout.watermark.width, height: layout.watermark.height, alignment: .trailing)
                    .offset(x: layout.watermark.x, y: layout.watermark.y)
            }
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }

    // MARK: - Photos

    private func assetID(for slot: CollageSlot) -> AssetID? {
        photoIDs.indices.contains(slot.photoIndex) ? photoIDs[slot.photoIndex] : nil
    }

    @ViewBuilder
    private func slotView(_ slot: CollageSlot) -> some View {
        let id = assetID(for: slot)
        let photo = CanvasPhoto(
            image: id.flatMap { images[$0] },
            size: slot.photoFrame.cgSize,
            isMissing: id.map { missing.contains($0) } ?? true
        )
        let isHighlighted = highlightedIndex == slot.photoIndex

        switch layout.style {
        case .polaroid, .scrapbook:
            ZStack(alignment: .topLeading) {
                theme.print
                photo.offset(x: slot.photoFrame.x - slot.frame.x, y: slot.photoFrame.y - slot.frame.y)
                if slot.hasTape {
                    tape(width: slot.frame.width, index: slot.photoIndex)
                }
            }
            .frame(width: slot.frame.width, height: slot.frame.height, alignment: .topLeading)
            .shadow(color: .black.opacity(layout.style == .scrapbook ? 0.22 : 0.16), radius: slot.frame.width * 0.025, y: slot.frame.width * 0.012)
            .overlay { if isHighlighted { highlight } }
            .placed(at: slot.frame, rotation: slot.rotation)
        default:
            photo
                .overlay { if isHighlighted { highlight } }
                .placed(at: slot.photoFrame, rotation: slot.rotation)
        }
    }

    private var highlight: some View {
        Rectangle().strokeBorder(Color.accentColor, lineWidth: 10)
    }

    /// Translucent paper tape across the top edge.
    private func tape(width: Double, index: Int) -> some View {
        let tapeWidth = min(220, max(90, width * 0.36))
        let tapeHeight = tapeWidth * 0.26
        return Rectangle()
            .fill(Color(red: 0.96, green: 0.93, blue: 0.84).opacity(0.82))
            .frame(width: tapeWidth, height: tapeHeight)
            .rotationEffect(.degrees(index.isMultiple(of: 3) ? -7 : 6))
            .offset(x: (width - tapeWidth) / 2, y: -tapeHeight * 0.45)
    }

    private func filmStrip(_ strip: FilmStrip) -> some View {
        let unit = (strip.isVertical ? strip.frame.width : strip.frame.height) / (1 + 2 * 0.17)
        return ZStack(alignment: .topLeading) {
            Color(red: 0.13, green: 0.12, blue: 0.11)
            SprocketHoles(isVertical: strip.isVertical, unit: unit)
                .fill(theme.background)
        }
        .placed(at: strip.frame)
    }

    // MARK: - Caption

    @ViewBuilder
    private func captionView(in rect: LayoutRect) -> some View {
        let unit = layout.canvas.width
        switch layout.style {
        case .film:
            Text([caption.title, caption.detail].compactMap { $0 }.joined(separator: "  ·  ").uppercased())
                .font(.system(size: unit * 0.024, weight: .medium, design: .monospaced))
                .tracking(unit * 0.003)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: rect.width, height: rect.height, alignment: .leading)
                .offset(x: rect.x, y: rect.y)
        case .editorial:
            VStack(alignment: .leading, spacing: unit * 0.006) {
                if let detail = caption.detail {
                    Text(detail.uppercased())
                        .font(.system(size: unit * 0.021, weight: .semibold))
                        .tracking(unit * 0.004)
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let title = caption.title {
                    Text(title)
                        .font(.system(size: unit * 0.078, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .bottomLeading)
            .offset(x: rect.x, y: rect.y)
        case .minimal, .polaroid:
            VStack(spacing: unit * 0.008) {
                if let title = caption.title {
                    Text(title)
                        .font(.system(size: unit * 0.042, weight: .regular, design: .serif))
                        .italic(layout.style == .polaroid)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let detail = caption.detail {
                    Text(detail.uppercased())
                        .font(.system(size: unit * 0.02, weight: .medium))
                        .tracking(unit * 0.003)
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .center)
            .offset(x: rect.x, y: rect.y)
        case .grid:
            VStack(alignment: .leading, spacing: unit * 0.006) {
                if let title = caption.title {
                    Text(title)
                        .font(.system(size: unit * 0.038, weight: .medium, design: .serif))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let detail = caption.detail {
                    Text(detail)
                        .font(.system(size: unit * 0.021))
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .leading)
            .offset(x: rect.x, y: rect.y)
        case .scrapbook:
            VStack(alignment: .leading, spacing: unit * 0.004) {
                if let title = caption.title {
                    Text(title)
                        .font(.system(size: unit * 0.036, weight: .medium, design: .serif))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let detail = caption.detail {
                    Text(detail)
                        .font(.system(size: unit * 0.019, design: .serif))
                        .italic()
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(.horizontal, unit * 0.024)
            .padding(.vertical, unit * 0.01)
            .background(theme.print.shadow(.drop(color: .black.opacity(0.15), radius: 4, y: 2)))
            .rotationEffect(.degrees(-1.5))
            .frame(width: rect.width, height: rect.height, alignment: .leading)
            .offset(x: rect.x, y: rect.y)
        }
    }
}
