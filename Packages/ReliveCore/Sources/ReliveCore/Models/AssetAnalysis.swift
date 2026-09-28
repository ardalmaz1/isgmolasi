import Foundation

/// Visual signals computed on-device from a small thumbnail.
///
/// Every field is optional or has a neutral default: analysis is best-effort and any single
/// request may fail without invalidating the rest.
public struct AssetAnalysis: Codable, Hashable, Sendable {
    /// Bump when the analyzer changes in a way that makes cached results stale.
    public static let currentVersion = 1

    public var version: Int
    /// Number of faces detected. Relive never tries to identify who they are.
    public var faceCount: Int
    /// Best face capture quality in the image, 0...1.
    public var faceCaptureQuality: Double?
    /// Normalized sharpness estimate, 0...1.
    public var sharpness: Double?
    /// Normalized aesthetic estimate, 0...1.
    public var aestheticScore: Double?
    /// True for receipts, documents, screenshots of text and similar non-memories.
    public var isUtility: Bool
    public var fingerprint: VisualFingerprint?
    public var failures: AnalysisFailures

    public init(
        version: Int = AssetAnalysis.currentVersion,
        faceCount: Int = 0,
        faceCaptureQuality: Double? = nil,
        sharpness: Double? = nil,
        aestheticScore: Double? = nil,
        isUtility: Bool = false,
        fingerprint: VisualFingerprint? = nil,
        failures: AnalysisFailures = []
    ) {
        self.version = version
        self.faceCount = faceCount
        self.faceCaptureQuality = faceCaptureQuality
        self.sharpness = sharpness
        self.aestheticScore = aestheticScore
        self.isUtility = isUtility
        self.fingerprint = fingerprint
        self.failures = failures
    }

    /// Analysis that could not look at the image at all (e.g. the thumbnail was unavailable).
    public static func unavailable(version: Int = AssetAnalysis.currentVersion) -> AssetAnalysis {
        AssetAnalysis(version: version, failures: [.thumbnailUnavailable])
    }

    public var isCurrent: Bool { version >= AssetAnalysis.currentVersion }
}

/// Which parts of the analysis failed. Used for diagnostics and graceful degradation.
public struct AnalysisFailures: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let thumbnailUnavailable = AnalysisFailures(rawValue: 1 << 0)
    public static let faceDetection = AnalysisFailures(rawValue: 1 << 1)
    public static let featurePrint = AnalysisFailures(rawValue: 1 << 2)
    public static let aesthetics = AnalysisFailures(rawValue: 1 << 3)
    public static let pixelMetrics = AnalysisFailures(rawValue: 1 << 4)
}
