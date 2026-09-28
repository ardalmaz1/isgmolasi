import Foundation

/// Thresholds for duplicate and near-identical detection.
///
/// Feature distances are Euclidean distances between unit-length embeddings (0 = identical,
/// ~1.4 = unrelated). The defaults are deliberately strict starting points to be tuned against
/// real libraries: hiding a photo by mistake is far worse than showing a near-copy.
public struct SimilarityConfiguration: Hashable, Sendable {
    /// Copies without embeddings — perceptual hash distance, out of 64 bits.
    public var duplicateHashDistance: Int
    /// Copies — embedding distance.
    public var duplicateFeatureDistance: Float
    /// Copies with embeddings — the hashes must also be at least this close.
    public var duplicateHashDistanceWithFeatures: Int
    /// Copies must have (nearly) the same shape; crops are not copies.
    public var duplicateAspectRatioTolerance: Double
    /// Hash-only copies must be at most this fraction of the original's pixel count (or have
    /// lost their location).
    public var resavedCopyMaximumResolutionRatio: Double

    /// Near-identical shots (bursts, "one more") — perceptual hash distance.
    public var similarHashDistance: Int
    /// Near-identical shots — embedding distance.
    public var similarFeatureDistance: Float
    /// Near-identical shots must be taken within this interval of the burst's first shot.
    public var similarMaximumTimeGap: TimeInterval

    /// Below this luminance contrast a perceptual hash is too noisy to trust.
    public var minimumReliableContrast: Double
    /// A hash with fewer set (or unset) bits than this describes a nearly flat image.
    public var minimumHashBits: Int

    public init(
        duplicateHashDistance: Int = 4,
        duplicateFeatureDistance: Float = 0.15,
        duplicateHashDistanceWithFeatures: Int = 8,
        duplicateAspectRatioTolerance: Double = 0.04,
        resavedCopyMaximumResolutionRatio: Double = 0.8,
        similarHashDistance: Int = 8,
        similarFeatureDistance: Float = 0.35,
        similarMaximumTimeGap: TimeInterval = 5 * 60,
        minimumReliableContrast: Double = 0.05,
        minimumHashBits: Int = 8
    ) {
        self.duplicateHashDistance = duplicateHashDistance
        self.duplicateFeatureDistance = duplicateFeatureDistance
        self.duplicateHashDistanceWithFeatures = duplicateHashDistanceWithFeatures
        self.duplicateAspectRatioTolerance = duplicateAspectRatioTolerance
        self.resavedCopyMaximumResolutionRatio = resavedCopyMaximumResolutionRatio
        self.similarHashDistance = similarHashDistance
        self.similarFeatureDistance = similarFeatureDistance
        self.similarMaximumTimeGap = similarMaximumTimeGap
        self.minimumReliableContrast = minimumReliableContrast
        self.minimumHashBits = minimumHashBits
    }

    public static let standard = SimilarityConfiguration()
}
