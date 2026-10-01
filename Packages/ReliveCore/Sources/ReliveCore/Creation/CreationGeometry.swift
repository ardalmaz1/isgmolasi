import Foundation

// Geometry for Relive's creations (collages, story cards, recap cards).
//
// Everything is laid out in *design points* on a canvas of fixed width (see
// `CreationAspectRatio.designWidth`). The preview draws that canvas scaled down and the export
// draws it scaled up, so both come from the same layout and always match.

/// A canvas size in design points.
public struct CanvasSize: Hashable, Sendable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Width divided by height.
    public var aspectRatio: Double { height > 0 ? width / height : 1 }
}

/// A rectangle in design points. Origin is the canvas's top-left corner; y grows downwards.
public struct LayoutRect: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }
    public var size: CanvasSize { CanvasSize(width: width, height: height) }

    /// Width divided by height.
    public var aspectRatio: Double { height > 0 ? width / height : 1 }

    public func insetBy(dx: Double, dy: Double) -> LayoutRect {
        LayoutRect(x: x + dx, y: y + dy, width: max(0, width - 2 * dx), height: max(0, height - 2 * dy))
    }

    /// The same rectangle scaled around its center.
    public func scaled(by factor: Double) -> LayoutRect {
        let newWidth = width * factor
        let newHeight = height * factor
        return LayoutRect(x: midX - newWidth / 2, y: midY - newHeight / 2, width: newWidth, height: newHeight)
    }

    public func offsetBy(dx: Double, dy: Double) -> LayoutRect {
        LayoutRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// True when the interiors overlap by more than `tolerance` points in both directions.
    public func overlaps(_ other: LayoutRect, tolerance: Double = 0.01) -> Bool {
        let horizontal = min(maxX, other.maxX) - max(minX, other.minX)
        let vertical = min(maxY, other.maxY) - max(minY, other.minY)
        return horizontal > tolerance && vertical > tolerance
    }

    public func contains(_ other: LayoutRect, tolerance: Double = 0.01) -> Bool {
        other.minX >= minX - tolerance && other.minY >= minY - tolerance
            && other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
    }

    /// Axis-aligned bounds after rotating by `degrees` around the center.
    public func rotatedBounds(degrees: Double) -> LayoutRect {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let boundsWidth = width * cosine + height * sine
        let boundsHeight = width * sine + height * cosine
        return LayoutRect(x: midX - boundsWidth / 2, y: midY - boundsHeight / 2, width: boundsWidth, height: boundsHeight)
    }
}

/// A point in unit coordinates of an image (0...1 on both axes, top-left origin).
public struct FocusPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Centered horizontally and slightly above center vertically: when a tall photo is cropped
    /// into a wider frame, faces are more often in the upper half than the lower.
    public static let standard = FocusPoint(x: 0.5, y: 0.42)
}

/// Coarse shape of a photo, used by layouts and by "Make it for me".
public enum PhotoOrientation: String, Hashable, Sendable, CaseIterable {
    case portrait
    case square
    case landscape
    case panorama

    public init(aspectRatio: Double) {
        switch aspectRatio {
        case ..<0.9: self = .portrait
        case 0.9...1.1: self = .square
        case 1.1...2.2: self = .landscape
        default: self = .panorama
        }
    }

    public var isPortrait: Bool { self == .portrait }
    public var isLandscape: Bool { self == .landscape || self == .panorama }
}

/// How a photo fills a frame: scaled to cover it, then cropped around a focus point.
public enum CropMath {
    /// Where to draw an image of `imageAspect` (width / height) so it covers a frame of
    /// `frameSize` completely, keeping `focus` as close to the frame's center as the image allows.
    /// The returned rect is relative to the frame's top-left corner and may extend past the frame;
    /// the caller clips to the frame.
    public static func fillRect(imageAspect: Double, frameSize: CanvasSize, focus: FocusPoint = .standard) -> LayoutRect {
        let aspect = sanitizedAspect(imageAspect)
        guard frameSize.width > 0, frameSize.height > 0 else {
            return LayoutRect(x: 0, y: 0, width: 0, height: 0)
        }
        let frameAspect = frameSize.width / frameSize.height
        let drawWidth: Double
        let drawHeight: Double
        if aspect > frameAspect {
            // Wider than the frame: match heights, crop the sides.
            drawHeight = frameSize.height
            drawWidth = frameSize.height * aspect
        } else {
            // Taller than the frame: match widths, crop top and bottom.
            drawWidth = frameSize.width
            drawHeight = frameSize.width / aspect
        }
        let x = clamp(frameSize.width / 2 - focus.x * drawWidth, min: frameSize.width - drawWidth, max: 0)
        let y = clamp(frameSize.height / 2 - focus.y * drawHeight, min: frameSize.height - drawHeight, max: 0)
        return LayoutRect(x: x, y: y, width: drawWidth, height: drawHeight)
    }

    /// The share of an image hidden when it fills a frame of another shape (0 = nothing hidden).
    public static func cropLoss(imageAspect: Double, frameAspect: Double) -> Double {
        let image = sanitizedAspect(imageAspect)
        let frame = sanitizedAspect(frameAspect)
        return 1 - min(image / frame, frame / image)
    }

    /// Unknown or broken dimensions are treated as square.
    public static func sanitizedAspect(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0 else { return 1 }
        return aspect
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.max(lower, Swift.min(upper, value))
    }
}

/// The three canvas shapes Relive creates.
public enum CreationAspectRatio: String, CaseIterable, Codable, Hashable, Sendable {
    /// 1:1 — feeds and messages.
    case square
    /// 4:5 — the tallest shape feeds show uncropped.
    case portrait
    /// 9:16 — full-screen stories.
    case story

    /// Every canvas is this many design points wide, so type and spacing are identical across
    /// shapes and between preview and export.
    public static let designWidth: Double = 1080
    /// Pixels per design point in exported images (2160 px wide).
    public static let exportScale: Double = 2

    public var widthOverHeight: Double {
        switch self {
        case .square: 1
        case .portrait: 4.0 / 5.0
        case .story: 9.0 / 16.0
        }
    }

    public var label: String {
        switch self {
        case .square: "1:1"
        case .portrait: "4:5"
        case .story: "9:16"
        }
    }

    public var designSize: CanvasSize {
        CanvasSize(width: Self.designWidth, height: (Self.designWidth / widthOverHeight).rounded())
    }

    /// Size of the exported image in pixels: 2160×2160, 2160×2700 or 2160×3840.
    public var exportPixelSize: (width: Int, height: Int) {
        let size = designSize
        return (Int((size.width * Self.exportScale).rounded()), Int((size.height * Self.exportScale).rounded()))
    }
}

/// Pixel sizes to request from the photo library.
public enum CreationImageSizing {
    /// Long side of the images used for interactive previews. Large enough for a sharp preview on
    /// a 3× display, small enough that a dozen of them stay cheap.
    public static let previewLongSide: Double = 1200
    /// Exports never ask for more than this per side, however large the original is.
    public static let maximumExportSide: Double = 4096

    /// Pixels needed to fill a frame of `frameSize` design points in the exported image.
    public static func exportPixelSize(forFrame frameSize: CanvasSize) -> CanvasSize {
        let scale = CreationAspectRatio.exportScale
        var width = (frameSize.width * scale).rounded(.up)
        var height = (frameSize.height * scale).rounded(.up)
        let longest = max(width, height)
        if longest > maximumExportSide {
            let factor = maximumExportSide / longest
            width = (width * factor).rounded(.up)
            height = (height * factor).rounded(.up)
        }
        return CanvasSize(width: max(1, width), height: max(1, height))
    }
}
