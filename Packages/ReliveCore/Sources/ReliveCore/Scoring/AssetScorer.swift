import Foundation

/// Weights for choosing a moment's cover. Kept as data so they can be tuned (or later learned)
/// without touching the selection logic.
///
/// Component signals are normalized to 0...1 and combined as a weighted average. Favorites and
/// penalties are applied on top of that average, so marking a photo as a favorite in the Photos
/// app is a strong signal regardless of how the other weights are tuned.
public struct HeroScoringWeights: Codable, Hashable, Sendable {
    public var faceQuality: Double
    /// Rewards photos with people in them; two faces (the two of you) fit best.
    public var faceCount: Double
    public var sharpness: Double
    public var aesthetics: Double
    public var resolution: Double
    /// Portrait and square images fill a 4:5 card best; panoramas fill it worst.
    public var orientation: Double
    /// A shot that isn't one of many near-identical takes.
    public var uniqueness: Double

    public var favoriteBonus: Double
    public var utilityPenalty: Double
    public var screenshotPenalty: Double
    public var videoPenalty: Double

    public init(
        faceQuality: Double = 0.30,
        faceCount: Double = 0.15,
        sharpness: Double = 0.20,
        aesthetics: Double = 0.20,
        resolution: Double = 0.05,
        orientation: Double = 0.10,
        uniqueness: Double = 0.05,
        favoriteBonus: Double = 0.50,
        utilityPenalty: Double = 0.60,
        screenshotPenalty: Double = 0.60,
        videoPenalty: Double = 0.10
    ) {
        self.faceQuality = faceQuality
        self.faceCount = faceCount
        self.sharpness = sharpness
        self.aesthetics = aesthetics
        self.resolution = resolution
        self.orientation = orientation
        self.uniqueness = uniqueness
        self.favoriteBonus = favoriteBonus
        self.utilityPenalty = utilityPenalty
        self.screenshotPenalty = screenshotPenalty
        self.videoPenalty = videoPenalty
    }

    public static let standard = HeroScoringWeights()
}

/// Scores how good an asset is as a representative image.
public struct AssetScorer: Sendable {
    /// Per-component contributions, useful for tests and future tuning tools.
    public struct Breakdown: Hashable, Sendable {
        public var faceQuality: Double
        public var faceCount: Double
        public var sharpness: Double
        public var aesthetics: Double
        public var resolution: Double
        public var orientation: Double
        public var uniqueness: Double
        public var bonus: Double
        public var penalty: Double
        public var total: Double
    }

    /// Value used for a signal we could not measure: neither rewards nor punishes.
    static let neutral = 0.5

    public var weights: HeroScoringWeights

    public init(weights: HeroScoringWeights = .standard) {
        self.weights = weights
    }

    public func score(_ asset: MemoryAsset, similarShotCount: Int = 0) -> Double {
        breakdown(asset, similarShotCount: similarShotCount).total
    }

    public func breakdown(_ asset: MemoryAsset, similarShotCount: Int = 0) -> Breakdown {
        let analysis = asset.analysis
        let analysisUsable = analysis.map { !$0.failures.contains(.thumbnailUnavailable) } ?? false

        let faceQuality: Double
        let faceCount: Double
        if analysisUsable, let analysis, !analysis.failures.contains(.faceDetection) {
            faceQuality = analysis.faceCount > 0 ? (analysis.faceCaptureQuality ?? Self.neutral) : 0
            faceCount = Self.faceCountSuitability(analysis.faceCount)
        } else {
            faceQuality = Self.neutral
            faceCount = Self.neutral
        }

        let sharpness = analysisUsable ? (analysis?.sharpness ?? Self.neutral) : Self.neutral
        let aesthetics = analysisUsable ? (analysis?.aestheticScore ?? Self.neutral) : Self.neutral
        let resolution = asset.megapixels > 0 ? min(1, asset.megapixels / 12) : Self.neutral
        let orientation = Self.orientationSuitability(asset.aspectRatio)
        let uniqueness = 1 / Double(1 + max(0, similarShotCount))

        let components: [(Double, Double)] = [
            (faceQuality, weights.faceQuality),
            (faceCount, weights.faceCount),
            (sharpness, weights.sharpness),
            (aesthetics, weights.aesthetics),
            (resolution, weights.resolution),
            (orientation, weights.orientation),
            (uniqueness, weights.uniqueness),
        ]
        var weightSum = 0.0
        var weighted = 0.0
        for (value, weight) in components {
            let clampedWeight = max(0, weight)
            weightSum += clampedWeight
            weighted += value * clampedWeight
        }
        let base = weightSum > 0 ? weighted / weightSum : Self.neutral

        let bonus = asset.isFavorite ? weights.favoriteBonus : 0
        var penalty = 0.0
        if analysis?.isUtility == true { penalty += weights.utilityPenalty }
        if asset.isScreenshot { penalty += weights.screenshotPenalty }
        if asset.kind == .video { penalty += weights.videoPenalty }

        return Breakdown(
            faceQuality: faceQuality,
            faceCount: faceCount,
            sharpness: sharpness,
            aesthetics: aesthetics,
            resolution: resolution,
            orientation: orientation,
            uniqueness: uniqueness,
            bonus: bonus,
            penalty: penalty,
            total: base + bonus - penalty
        )
    }

    static func faceCountSuitability(_ count: Int) -> Double {
        switch count {
        case 0: 0
        case 1: 0.7
        case 2: 1
        case 3...5: 0.75
        default: 0.5
        }
    }

    static func orientationSuitability(_ aspectRatio: Double?) -> Double {
        guard let ratio = aspectRatio else { return neutral }
        switch ratio {
        case 0.55...1.05: return 1      // portrait and square
        case 1.05...1.8: return 0.75    // regular landscape
        default: return 0.3             // panoramas, very tall crops
        }
    }
}
