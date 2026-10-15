import Foundation

/// The film over time: which photos are on screen at a moment, how opaque, how far into their
/// motion, how much black, and which words. Both the live preview and the exporter draw from
/// this, so a preview never surprises an export.
public struct MovieTimeline: Sendable {
    /// Seconds the film takes to fade in from black, and to fade out at the end.
    public static let fadeIn = 0.8
    public static let fadeOut = 1.0

    public let plan: MoviePlan
    /// When each scene starts.
    public let starts: [Double]
    public let duration: Double

    public init(plan: MoviePlan) {
        self.plan = plan
        var starts: [Double] = []
        var end = 0.0
        for (index, scene) in plan.scenes.enumerated() {
            let start = index == 0 ? 0 : end - Self.overlap(scene)
            starts.append(start)
            end = start + scene.duration
        }
        self.starts = starts
        duration = end
    }

    /// A crossfade lays the new photo over the end of the previous one; the other transitions
    /// don't overlap.
    static func overlap(_ scene: MovieScene) -> Double {
        scene.transition == .crossfade ? scene.transitionDuration : 0
    }

    public struct Layer: Hashable, Sendable {
        public var sceneIndex: Int
        public var opacity: Double
        /// 0 at the scene's first frame, 1 at its last.
        public var progress: Double
    }

    public struct Caption: Hashable, Sendable {
        public var sceneIndex: Int
        public var text: MovieText
        public var opacity: Double
    }

    public struct Frame: Hashable, Sendable {
        /// Bottom to top.
        public var layers: [Layer]
        /// Black drawn over everything (fades).
        public var blackOpacity: Double
        public var captions: [Caption]
    }

    /// What is on screen at `time` seconds.
    public func frame(at time: Double) -> Frame {
        let t = min(max(0, time), max(0, duration - 0.0001))
        var layers: [Layer] = []
        var captions: [Caption] = []
        var black = 0.0
        for (index, scene) in plan.scenes.enumerated() {
            let start = starts[index]
            let end = start + scene.duration
            guard t >= start, t < end else { continue }
            let local = t - start
            var opacity = 1.0
            if index > 0, scene.transition == .crossfade, scene.transitionDuration > 0 {
                opacity = Self.ease(min(1, local / scene.transitionDuration))
            }
            layers.append(Layer(sceneIndex: index, opacity: opacity, progress: min(1, local / max(scene.duration, 0.001))))

            // Fades through black: out over the end of this scene when the next one asks for it,
            // in over its own start.
            if index == 0 {
                black = max(black, 1 - Self.ease(min(1, local / Self.fadeIn)))
            } else if scene.transition == .fadeThroughBlack {
                let half = scene.transitionDuration / 2
                if half > 0, local < half { black = max(black, 1 - Self.ease(local / half)) }
            }
            if index + 1 < plan.scenes.count {
                let next = plan.scenes[index + 1]
                let half = next.transitionDuration / 2
                if next.transition == .fadeThroughBlack, half > 0, end - t < half {
                    black = max(black, Self.ease(1 - (end - t) / half))
                }
            }
            if let text = scene.text {
                captions.append(Caption(sceneIndex: index, text: text, opacity: captionOpacity(local: local, scene: scene, isLast: index == plan.scenes.count - 1)))
            }
        }
        if duration - t < Self.fadeOut {
            black = max(black, Self.ease(1 - (duration - t) / Self.fadeOut))
        }
        // When a crossfade is complete the lower photo no longer shows; drop fully hidden layers.
        if let topOpaque = layers.lastIndex(where: { $0.opacity >= 1 }) {
            layers.removeFirst(topOpaque)
        }
        return Frame(layers: layers, blackOpacity: min(1, max(0, black)), captions: captions.filter { $0.opacity > 0.001 })
    }

    /// Words appear a moment after their photo and leave before it does (the last ones stay).
    private func captionOpacity(local: Double, scene: MovieScene, isLast: Bool) -> Double {
        let delay = scene.role == .opening ? 0.6 : 0.4
        let fade = 0.5
        let appear = Self.ease(min(1, max(0, (local - delay) / fade)))
        if isLast { return appear }
        let leave = Self.ease(min(1, max(0, (scene.duration - 0.35 - local) / 0.4)))
        return min(appear, leave)
    }

    /// Smooth start and end.
    static func ease(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

/// Where a scene's photo is drawn on the canvas at a point in its motion. Pure math, shared by
/// preview and export.
public enum MovieGeometry {
    /// The most a photo is enlarged by motion: barely noticeable, never a lunge at a face.
    public static let zoomAmount = 0.07
    /// The share of the available slack a pan travels.
    public static let panTravel = 0.6

    /// The photo's rect (relative to the canvas's top-left; it may extend past the canvas, which
    /// clips it). For `.fit` scenes this is the whole photo; see `backgroundRect` for the
    /// softened copy behind it.
    public static func imageRect(for scene: MovieScene, canvas: CanvasSize, progress: Double) -> LayoutRect {
        let eased = MovieTimeline.ease(progress)
        switch scene.framing {
        case .fit:
            let fit = fitRect(imageAspect: scene.imageAspect, canvas: canvas)
            let scale: Double = switch scene.motion {
            case .zoomIn: 1 + 0.04 * eased
            case .zoomOut: 1.04 - 0.04 * eased
            default: 1
            }
            return fit.scaledAround(x: canvas.width / 2, y: canvas.height / 2, factor: scale)
        case .fill:
            let base = CropMath.fillRect(imageAspect: scene.imageAspect, frameSize: canvas, focus: scene.focus)
            let scale: Double = switch scene.motion {
            case .zoomIn: 1 + zoomAmount * eased
            case .zoomOut: 1 + zoomAmount * (1 - eased)
            case .still: 1
            default: 1 + zoomAmount * 0.6
            }
            // Scale around the focus point as it sits on the canvas, so it stays put.
            let anchorX = base.x + scene.focus.x * base.width
            let anchorY = base.y + scene.focus.y * base.height
            var rect = base.scaledAround(x: anchorX, y: anchorY, factor: scale)
            rect = rect.clampedToCover(canvas)
            guard scene.motion.isPan else { return rect }
            let slackX = rect.width - canvas.width
            let slackY = rect.height - canvas.height
            let travel = panTravel / 2
            let offset: (Double, Double) = switch scene.motion {
            // The view moves left: the photo slides right.
            case .panLeft: (slackX * travel * (2 * eased - 1), 0)
            case .panRight: (-slackX * travel * (2 * eased - 1), 0)
            case .panUp: (0, slackY * travel * (2 * eased - 1))
            case .panDown: (0, -slackY * travel * (2 * eased - 1))
            default: (0, 0)
            }
            return rect.offsetBy(dx: offset.0, dy: offset.1).clampedToCover(canvas)
        }
    }

    /// For `.fit` scenes: the softened copy behind the photo, filling the canvas.
    public static func backgroundRect(for scene: MovieScene, canvas: CanvasSize) -> LayoutRect {
        CropMath.fillRect(imageAspect: scene.imageAspect, frameSize: canvas, focus: FocusPoint(x: 0.5, y: 0.5))
            .scaledAround(x: canvas.width / 2, y: canvas.height / 2, factor: 1.15)
    }

    /// The whole photo, as large as fits with a small margin, centered a touch above the middle.
    static func fitRect(imageAspect: Double, canvas: CanvasSize) -> LayoutRect {
        let aspect = CropMath.sanitizedAspect(imageAspect)
        let margin = 0.0
        let maxWidth = canvas.width - 2 * margin
        let maxHeight = canvas.height - 2 * margin
        var width = maxWidth
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        let x = (canvas.width - width) / 2
        let y = (canvas.height - height) / 2 - (canvas.height - height) * 0.06
        return LayoutRect(x: x, y: y, width: width, height: height)
    }

    /// The pixel size to load a scene's photo at: enough for the largest it is drawn, no more.
    public static func loadSize(for scene: MovieScene, canvas: CanvasSize) -> CanvasSize {
        let start = imageRect(for: scene, canvas: canvas, progress: 0)
        let end = imageRect(for: scene, canvas: canvas, progress: 1)
        let width = max(start.width, end.width)
        let height = max(start.height, end.height)
        return CanvasSize(width: width.rounded(.up), height: height.rounded(.up))
    }
}

extension LayoutRect {
    func scaledAround(x anchorX: Double, y anchorY: Double, factor: Double) -> LayoutRect {
        LayoutRect(
            x: anchorX - (anchorX - x) * factor,
            y: anchorY - (anchorY - y) * factor,
            width: width * factor,
            height: height * factor
        )
    }

    /// Moved (not resized) so it still covers the canvas, when it is large enough to.
    func clampedToCover(_ canvas: CanvasSize) -> LayoutRect {
        var rect = self
        if rect.width >= canvas.width {
            rect.x = min(0, max(canvas.width - rect.width, rect.x))
        }
        if rect.height >= canvas.height {
            rect.y = min(0, max(canvas.height - rect.height, rect.y))
        }
        return rect
    }
}
