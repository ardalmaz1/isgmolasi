import Foundation

/// Identifier of an asset. We use the photo library's local identifier directly, which is
/// stable across launches and lets us re-resolve the asset without copying any pixels.
public typealias AssetID = String

public enum MediaKind: String, Codable, Hashable, Sendable {
    case photo
    case video
}

/// Media subtypes that matter to the engine. Mirrors a subset of PhotoKit's subtypes
/// without depending on PhotoKit.
public struct AssetTraits: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let screenshot = AssetTraits(rawValue: 1 << 0)
    public static let livePhoto = AssetTraits(rawValue: 1 << 1)
    public static let panorama = AssetTraits(rawValue: 1 << 2)
    public static let depthEffect = AssetTraits(rawValue: 1 << 3)
}

/// A photo or video the user chose to share with Relive.
///
/// This is a value snapshot of the metadata we could read locally. It never holds pixel data
/// and never references a PhotoKit object, so it can be persisted, tested and passed across
/// concurrency domains freely.
public struct MemoryAsset: Identifiable, Codable, Hashable, Sendable {
    public var id: AssetID { localIdentifier }

    public let localIdentifier: AssetID
    public var creationDate: Date?
    public var location: GeoCoordinate?
    public var kind: MediaKind
    public var traits: AssetTraits
    /// Seconds; zero for photos.
    public var duration: TimeInterval
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isFavorite: Bool
    /// On-device visual signals. `nil` until the analysis stage has run.
    public var analysis: AssetAnalysis?

    public init(
        localIdentifier: AssetID,
        creationDate: Date?,
        location: GeoCoordinate? = nil,
        kind: MediaKind = .photo,
        traits: AssetTraits = [],
        duration: TimeInterval = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        isFavorite: Bool = false,
        analysis: AssetAnalysis? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.location = location
        self.kind = kind
        self.traits = traits
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.analysis = analysis
    }

    /// Width divided by height, when dimensions are known.
    public var aspectRatio: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    public var megapixels: Double {
        Double(max(0, pixelWidth)) * Double(max(0, pixelHeight)) / 1_000_000
    }

    public var isScreenshot: Bool { traits.contains(.screenshot) }
}
