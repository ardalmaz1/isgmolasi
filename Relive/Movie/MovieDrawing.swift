import CoreImage
import ReliveCore
import UIKit

/// Pixels for one scene: the whole photo, sized for the largest it is drawn (never the original),
/// and for "fit" scenes a small softened copy for the background.
struct MovieSceneImages: @unchecked Sendable {
    let photo: UIImage
    let background: UIImage?
}

/// Draws one frame of a movie. The live preview and the exporter both call this with the same
/// `MovieTimeline.Frame`, so a preview looks like the exported film (only smaller).
///
/// The context's origin is top-left (UIKit's convention) and UIKit is pushed on it.
enum MovieFrameDrawer {
    static func draw(
        _ frame: MovieTimeline.Frame,
        plan: MoviePlan,
        in context: CGContext,
        size: CGSize,
        images: [Int: MovieSceneImages]
    ) {
        let canvas = plan.settings.aspect.renderSize
        let scale = size.width / canvas.width
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)

        UIColor.black.setFill()
        context.fill(bounds)

        for layer in frame.layers {
            let scene = plan.scenes[layer.sceneIndex]
            context.saveGState()
            context.setAlpha(layer.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            if let pixels = images[layer.sceneIndex] {
                if scene.framing == .fit {
                    if let background = pixels.background {
                        background.draw(in: MovieGeometry.backgroundRect(for: scene, canvas: canvas).cgRect)
                    }
                    UIColor(white: 0, alpha: 0.28).setFill()
                    context.fill(bounds)
                }
                pixels.photo.draw(in: MovieGeometry.imageRect(for: scene, canvas: canvas, progress: layer.progress).cgRect)
            } else {
                // Not loaded yet (preview) or gone: a quiet dark frame, never someone else's photo.
                UIColor(white: 0.12, alpha: 1).setFill()
                context.fill(bounds)
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }

        grade(plan.settings.style, in: context, bounds: bounds)

        for caption in frame.captions {
            MovieCaptionDrawer.draw(caption.text, style: plan.settings.style, isOpening: plan.scenes[caption.sceneIndex].role == .opening, canvas: canvas, opacity: caption.opacity, in: context)
        }

        if frame.blackOpacity > 0 {
            UIColor(white: 0, alpha: frame.blackOpacity).setFill()
            context.fill(bounds)
        }
        context.restoreGState()
    }

    /// The style's colour: a light warm wash for Film and Warm, a soft vignette for Film.
    private static func grade(_ style: MovieStyle, in context: CGContext, bounds: CGRect) {
        switch style {
        case .classic, .editorial:
            return
        case .film:
            UIColor(red: 1, green: 0.66, blue: 0.36, alpha: 0.07).setFill()
            context.fill(bounds)
            vignette(in: context, bounds: bounds, strength: 0.35)
        case .warm:
            UIColor(red: 1, green: 0.8, blue: 0.6, alpha: 0.06).setFill()
            context.fill(bounds)
        }
    }

    private static func vignette(in context: CGContext, bounds: CGRect, strength: CGFloat) {
        let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: strength).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 1]) else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = hypot(bounds.width, bounds.height) / 2
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    }
}

/// The few words in a movie, set per style. Drawn, not burned into photos.
enum MovieCaptionDrawer {
    static func draw(_ text: MovieText, style: MovieStyle, isOpening: Bool, canvas: CanvasSize, opacity: Double, in context: CGContext) {
        let unit = min(canvas.width, canvas.height) / 1080
        let margin = 72 * unit
        let width = canvas.width - 2 * margin
        let alignment: NSTextAlignment = (style == .editorial || style == .film) ? .left : .center

        let lines = attributedLines(text, style: style, isOpening: isOpening, unit: unit, alignment: alignment)
        let heights = lines.map { $0.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height.rounded(.up) }
        let spacing = 14 * unit
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        let bottom: CGFloat = switch style {
        case .warm: canvas.height * 0.78
        case .classic: canvas.height * 0.84
        case .editorial, .film: canvas.height - margin * 1.4
        }
        var y = bottom - total

        // A soft shade behind the words keeps them legible on bright photos.
        context.saveGState()
        context.setAlpha(opacity)
        let shadeTop = max(0, y - 140 * unit)
        let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.42).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: shadeTop), end: CGPoint(x: 0, y: min(canvas.height, bottom + 120 * unit)), options: [.drawsAfterEndLocation])
        }
        context.setShadow(offset: .zero, blur: 14 * unit, color: UIColor(white: 0, alpha: 0.45).cgColor)
        for (line, height) in zip(lines, heights) {
            line.draw(with: CGRect(x: margin, y: y, width: width, height: height), options: [.usesLineFragmentOrigin], context: nil)
            y += height + spacing
        }
        context.restoreGState()
    }

    private static func attributedLines(_ text: MovieText, style: MovieStyle, isOpening: Bool, unit: CGFloat, alignment: NSTextAlignment) -> [NSAttributedString] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let ink = style == .film ? UIColor(red: 1, green: 0.94, blue: 0.84, alpha: 1) : UIColor.white

        func font(_ size: CGFloat, _ weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont {
            let base = UIFont.systemFont(ofSize: size * unit, weight: weight)
            return base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size * unit) } ?? base
        }
        let titleSize: CGFloat = isOpening ? 76 : 58
        let (eyebrowFont, titleFont, detailFont): (UIFont, UIFont, UIFont) = switch style {
        case .classic: (font(25, .semibold, design: .default), font(titleSize, .regular, design: .serif), font(25, .medium, design: .default))
        case .editorial: (font(24, .semibold, design: .default), font(titleSize * 0.9, .semibold, design: .default), font(24, .medium, design: .default))
        case .film: (font(24, .regular, design: .monospaced), font(titleSize * 0.62, .regular, design: .monospaced), font(23, .regular, design: .monospaced))
        case .warm: (font(25, .medium, design: .rounded), font(titleSize, .semibold, design: .rounded), font(25, .medium, design: .rounded))
        }

        var lines: [NSAttributedString] = []
        if let eyebrow = text.eyebrow, !eyebrow.isEmpty {
            lines.append(NSAttributedString(string: eyebrow.uppercased(), attributes: [
                .font: eyebrowFont, .foregroundColor: ink.withAlphaComponent(0.88), .kern: 3 * unit, .paragraphStyle: paragraph,
            ]))
        }
        let title = style == .film || style == .editorial ? text.title.uppercased() : text.title
        lines.append(NSAttributedString(string: title, attributes: [
            .font: titleFont, .foregroundColor: ink, .kern: (style == .film || style == .editorial ? 2 : 0) * unit, .paragraphStyle: paragraph,
        ]))
        if let detail = text.detail, !detail.isEmpty {
            lines.append(NSAttributedString(string: detail, attributes: [
                .font: detailFont, .foregroundColor: ink.withAlphaComponent(0.8), .kern: 1 * unit, .paragraphStyle: paragraph,
            ]))
        }
        return lines
    }
}

/// Loads a scene's pixels: the whole photo at the size it is drawn (capped), and its softened
/// copy for "fit" scenes. Exports don't cache; previews do (small sizes).
struct MovieImageLoader: Sendable {
    let loader: any CreationPhotoLoading
    /// 1 for export; smaller for previews.
    var scale: Double = 1
    var caches = false

    private final class SharedContext: @unchecked Sendable {
        let context = CIContext(options: [.cacheIntermediates: false])
    }
    private static let shared = SharedContext()

    func images(for scene: MovieScene, aspect: MovieAspect) async -> MovieSceneImages? {
        let canvas = aspect.renderSize
        let size = MovieGeometry.loadSize(for: scene, canvas: canvas)
        let longest = max(canvas.width, canvas.height) * 1.6
        let fit = min(1, longest / max(size.width, size.height))
        let pixels = CGSize(width: max(8, size.width * fit * scale), height: max(8, size.height * fit * scale))
        guard let photo = await loader.image(for: scene.assetID, pixelSize: pixels, contentMode: .aspectFit, caches: caches) else { return nil }
        let background = scene.framing == .fit ? await Self.softened(photo) : nil
        return MovieSceneImages(photo: photo, background: background)
    }

    /// A small, blurred, slightly darker copy (computed once per scene, off the main thread).
    static func softened(_ image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return nil }
            let input = CIImage(cgImage: cgImage).oriented(CGImagePropertyOrientation(image.imageOrientation))
            let small = input.transformed(by: CGAffineTransform(scaleX: 0.15, y: 0.15))
            let blurred = small.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06, kCIInputSaturationKey: 0.9])
                .cropped(to: small.extent)
            guard let rendered = shared.context.createCGImage(blurred, from: small.extent) else { return nil }
            return UIImage(cgImage: rendered)
        }.value
    }
}

extension LayoutRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
