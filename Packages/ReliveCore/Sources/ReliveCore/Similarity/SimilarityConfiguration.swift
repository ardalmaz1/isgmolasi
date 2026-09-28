import Foundation

/// Thresholds for duplicate and near-identical detection.
///
/// Feature distances are Euclidean distances between unit-length embeddings (0 = identical,
/// ~1.4 = unrelated). The defaults are conservative starting points and are expected to be
/// tuned against real libraries; hiding a photo by mistake is worse than showing a near-copy.
public struct SimilarityConfiguration: Hashable, Sendable {
    /// Copies (resized/recompressed) — perceptual hash distance, out of 64 bits.
    public var duplicateHashDistance: Int
    /// Copies — embedding distance.
    public var duplicateFeatureDistance: Float
    /// When embeddings agree on a duplicate, the hashes must still be at least this close.
    public var duplicateHashDistanceWithFeatures: Int
    /// Copies must have (nearly) the same shape; crops are not copies.
    public var duplicateAspectRatioTolerance: Double

    /// Near-identical shots (bursts, "one more") — perceptual hash distance.
    public var similarHashDistance: Int
    /// Near-identical shots — embedding distance.
    public var similarFeatureDistance: Float
    /// Near-identical shots must be taken within this interval of each other.
    public var similarMaximumTimeGap: TimeInterval

    /// Below this luminance contrast a perceptual hash is too noisy to trust on its own.
    public var minimumReliableContrast: Double

    public init(
        duplicateHashDistance: Int = 5,
        duplicateFeatureDistance: Float = 0.25,
        duplicateHashDistanceWithFeatures: Int = 12,
        duplicateAspectRatioTolerance: Double = 0.04,
        similarHashDistance: Int = 10,
        similarFeatureDistance: Float = 0.45,
        similarMaximumTimeGap: TimeInterval = 5 * 60,
        minimumReliableContrast: Double = 0.05
    ) {
        self.duplicateHashDistance = duplicateHashDistance
        self.duplicateFeatureDistance = duplicateFeatureDistance
        self.duplicateHashDistanceWithFeatures = duplicateHashDistanceWithFeatures
        self.duplicateAspectRatioTolerance = duplicateAspectRatioTolerance
        self.similarHashDistance = similarHashDistance
        self.similarFeatureDistance = similarFeatureDistance
        self.similarMaximumTimeGap = similarMaximumTimeGap
        self.minimumReliableContrast = minimumReliableContrast
    }

    public static let standard = SimilarityConfiguration()
}
