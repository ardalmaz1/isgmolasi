import ReliveCore
import SwiftUI
import UIKit

// Shared building blocks for everything Relive renders: collages, story cards, recap cards.
//
// Canvases are drawn in design points (1080 wide) with fixed type sizes. The preview shows the
// very same view scaled down (`ScaledCanvas`) and the export renders it scaled up
// (`CreationRenderer`), so what is saved is what was seen.

/// Images for a canvas, keyed by asset. Missing keys draw a quiet placeholder.
typealias CanvasImages = [AssetID: UIImage]

extension LayoutRect {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

extension CanvasSize {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// A photo cropped to fill a frame, around the shared focus point.
struct CanvasPhoto: View {
    let image: UIImage?
    let size: CGSize
    var isMissing = false
    var placeholder = Color(red: 0.86, green: 0.84, blue: 0.8)

    var body: some View {
        placeholder
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                if let image {
                    let rect = CropMath.fillRect(
                        imageAspect: image.size.width / max(image.size.height, 1),
                        frameSize: CanvasSize(width: size.width, height: size.height)
                    )
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.x, y: rect.y)
                }
            }
            .overlay {
                if image == nil && isMissing {
                    Image(systemName: "photo")
                        .font(.system(size: max(12, min(size.width, size.height) * 0.18)))
                        .foregroundStyle(Color.black.opacity(0.3))
                }
            }
            .clipped()
    }
}

/// Shows a canvas designed at `designSize` scaled to fit the available space.
struct ScaledCanvas<Content: View>: View {
    let designSize: CanvasSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = max(0.01, min(proxy.size.width / designSize.width, proxy.size.height / designSize.height))
            content()
                .frame(width: designSize.width, height: designSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: designSize.width * scale, height: designSize.height * scale, alignment: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(designSize.width / designSize.height, contentMode: .fit)
    }
}

/// The quiet mark on exported images.
struct MadeWithRelive: View {
    var size: CGFloat = 20
    var color: Color

    var body: some View {
        Text("Made with Relive")
            .font(.system(size: size, weight: .medium, design: .serif))
            .tracking(size * 0.08)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Sprocket holes along both long edges of a film strip.
struct SprocketHoles: Shape {
    var isVertical: Bool
    /// The frame's short side, which sets the hole size.
    var unit: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let holeLength = unit * 0.1
        let holeDepth = unit * 0.075
        let pitch = unit * 0.2
        let band = unit * 0.17
        let length = isVertical ? rect.height : rect.width
        let count = max(0, Int((length - pitch * 0.5) / pitch))
        let start = (length - CGFloat(count) * pitch) / 2 + (pitch - holeLength) / 2
        for index in 0..<count {
            let along = start + CGFloat(index) * pitch
            for side in [0, 1] {
                let across = side == 0 ? (band - holeDepth) / 2 : (isVertical ? rect.width : rect.height) - band + (band - holeDepth) / 2
                let hole = isVertical
                    ? CGRect(x: rect.minX + across, y: rect.minY + along, width: holeDepth, height: holeLength)
                    : CGRect(x: rect.minX + along, y: rect.minY + across, width: holeLength, height: holeDepth)
                path.addRoundedRect(in: hole, cornerSize: CGSize(width: holeDepth * 0.25, height: holeDepth * 0.25))
            }
        }
        return path
    }
}

extension View {
    /// Places a view at a design-point rectangle on a top-leading canvas.
    func placed(at rect: LayoutRect, rotation: Double = 0) -> some View {
        frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .rotationEffect(.degrees(rotation))
            .offset(x: rect.x, y: rect.y)
    }
}

/// Renders canvases to images, on device.
@MainActor
enum CreationRenderer {
    /// Renders `view`, laid out at `size` design points, at the export scale (2160 px wide).
    static func render<Content: View>(_ view: Content, size: CanvasSize) -> UIImage? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = CreationAspectRatio.exportScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
