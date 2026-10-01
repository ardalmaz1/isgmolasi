import Foundation

/// What "Make it for me" needs to know about one photo.
public struct CollagePhotoInfo: Hashable, Sendable {
    public var id: AssetID
    /// Width / height; unknown values count as square.
    public var aspectRatio: Double
    /// How good the photo is as a lead image (see `AssetScorer`).
    public var quality: Double
    public var date: Date?

    public init(id: AssetID, aspectRatio: Double, quality: Double, date: Date?) {
        self.id = id
        self.aspectRatio = aspectRatio
        self.quality = quality
        self.date = date
    }

    public init(asset: MemoryAsset, scorer: AssetScorer = AssetScorer()) {
        self.init(id: asset.id, aspectRatio: asset.aspectRatio ?? 1, quality: scorer.score(asset), date: asset.creationDate)
    }
}

/// One complete suggestion: a style, a canvas shape and the order of the photos.
public struct CollageSuggestion: Hashable, Sendable {
    public var style: CollageStyle
    public var aspectRatio: CreationAspectRatio
    public var order: [AssetID]
    public var score: Double
}

/// "Make it for me": chooses a style, a shape and an order for the selected photos, locally and
/// deterministically — no remote service, and the same photos always give the same answer.
///
/// The best photo leads (it gets the largest slot in Editorial and sits on top in Scrapbook);
/// the rest follow in the order they were taken, so a collage reads like the day did. Every
/// style × shape is laid out and scored on how large the photos end up, how much of them is
/// cropped, and how well the style suits the number of photos.
public struct CollageAutoDesigner: Sendable {
    public var engine: CollageLayoutEngine

    public init(engine: CollageLayoutEngine = CollageLayoutEngine()) {
        self.engine = engine
    }

    /// The photos in suggested order: best first, then chronological (undated last).
    public func suggestedOrder(_ photos: [CollagePhotoInfo]) -> [CollagePhotoInfo] {
        guard let lead = photos.min(by: Self.leadsBefore) else { return [] }
        let rest = photos.filter { $0.id != lead.id }.sorted(by: Self.chronological)
        return [lead] + rest
    }

    /// Every style × shape, best first.
    public func suggestions(for photos: [CollagePhotoInfo], caption: CollageCaptionSpec) -> [CollageSuggestion] {
        let ordered = suggestedOrder(photos)
        guard !ordered.isEmpty else { return [] }
        let aspects = ordered.map(\.aspectRatio)
        let ids = ordered.map(\.id)

        var results: [CollageSuggestion] = []
        for style in CollageStyle.allCases {
            for ratio in CreationAspectRatio.allCases {
                let layout = engine.layout(photoAspects: aspects, style: style, canvas: ratio.designSize, caption: caption)
                let score = Self.score(layout, aspects: aspects)
                    + Self.styleFit(style, count: ordered.count)
                    + Self.shapeFit(ratio)
                results.append(CollageSuggestion(style: style, aspectRatio: ratio, order: ids, score: score))
            }
        }
        return results.sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) > 1e-9 { return lhs.score > rhs.score }
            if lhs.style != rhs.style { return Self.styleRank(lhs.style) < Self.styleRank(rhs.style) }
            return Self.shapeRank(lhs.aspectRatio) < Self.shapeRank(rhs.aspectRatio)
        }
    }

    /// The best suggestion for each of the top `limit` styles, so pressing "Make it for me" again
    /// offers a genuinely different look rather than the same style in another shape.
    public func distinctSuggestions(for photos: [CollagePhotoInfo], caption: CollageCaptionSpec, limit: Int = 3) -> [CollageSuggestion] {
        var seen = Set<CollageStyle>()
        var picked: [CollageSuggestion] = []
        for suggestion in suggestions(for: photos, caption: caption) where seen.insert(suggestion.style).inserted {
            picked.append(suggestion)
            if picked.count == limit { break }
        }
        return picked
    }

    // MARK: - Scoring

    static func score(_ layout: CollageLayout, aspects: [Double]) -> Double {
        let canvasArea = layout.canvas.width * layout.canvas.height
        guard canvasArea > 0, !layout.slots.isEmpty else { return -10 }
        var coverage = 0.0
        var crop = 0.0
        var smallest = Double.greatestFiniteMagnitude
        for slot in layout.slots {
            let area = slot.photoFrame.area / canvasArea
            coverage += area
            smallest = min(smallest, area)
            let aspect = aspects[slot.photoIndex]
            let loss = CropMath.cropLoss(imageAspect: aspect, frameAspect: slot.photoFrame.aspectRatio)
            // The lead photo's crop matters most.
            crop += slot.photoIndex == 0 ? loss * 2 : loss
        }
        crop /= Double(layout.slots.count + 1)
        var score = coverage - 1.1 * crop
        if smallest < 0.02 { score -= 0.25 }
        return score
    }

    static func styleFit(_ style: CollageStyle, count: Int) -> Double {
        switch count {
        case ...3:
            switch style {
            case .editorial: 0.12
            case .minimal: 0.1
            case .polaroid: 0.1
            case .scrapbook: 0.02
            case .film: 0
            case .grid: -0.06
            }
        case 4...6:
            switch style {
            case .editorial: 0.1
            case .polaroid: 0.08
            case .scrapbook: 0.07
            case .film: 0.05
            case .grid: 0.05
            case .minimal: 0.04
            }
        default:
            switch style {
            case .grid: 0.12
            case .minimal: 0.07
            case .film: 0.06
            case .scrapbook: 0.03
            case .polaroid: -0.02
            case .editorial: -0.04
            }
        }
    }

    /// 4:5 shows uncropped in feeds and messages, so it is the gentle default.
    static func shapeFit(_ ratio: CreationAspectRatio) -> Double {
        switch ratio {
        case .portrait: 0.05
        case .square: 0.01
        case .story: -0.02
        }
    }

    static func styleRank(_ style: CollageStyle) -> Int {
        CollageStyle.allCases.firstIndex(of: style) ?? 0
    }

    static func shapeRank(_ ratio: CreationAspectRatio) -> Int {
        [CreationAspectRatio.portrait, .square, .story].firstIndex(of: ratio) ?? 0
    }

    static func leadsBefore(_ lhs: CollagePhotoInfo, _ rhs: CollagePhotoInfo) -> Bool {
        if abs(lhs.quality - rhs.quality) > 1e-9 { return lhs.quality > rhs.quality }
        return chronological(lhs, rhs)
    }

    static func chronological(_ lhs: CollagePhotoInfo, _ rhs: CollagePhotoInfo) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }
}
