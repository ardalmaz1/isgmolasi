import Foundation

/// Facts a naming service may use. Deliberately contains no pixels and no emotional context:
/// names describe *when* and *where*, never how it felt.
public struct MomentNamingContext: Hashable, Sendable {
    public var kind: Moment.Kind
    public var start: Date?
    public var end: Date?
    public var place: PlaceName?
    /// Place of the enclosing chapter, when the moment is part of a trip.
    public var chapterPlace: PlaceName?
    public var isInChapter: Bool
    public var assetCount: Int

    public init(
        kind: Moment.Kind,
        start: Date?,
        end: Date?,
        place: PlaceName?,
        chapterPlace: PlaceName? = nil,
        isInChapter: Bool = false,
        assetCount: Int
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.place = place
        self.chapterPlace = chapterPlace
        self.isInChapter = isInChapter
        self.assetCount = assetCount
    }
}

public struct ChapterNamingContext: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var place: PlaceName?
    public var momentCount: Int

    public init(start: Date, end: Date, place: PlaceName?, momentCount: Int) {
        self.start = start
        self.end = end
        self.place = place
        self.momentCount = momentCount
    }
}

/// Produces titles for moments and chapters.
///
/// Prototype 0.1 ships `LocalMomentNamingService`, which is deterministic and factual. The
/// protocol is async so a future implementation can consult a model — it would receive the
/// same factual context and must keep the same rule: describe, never interpret.
public protocol MomentNamingService: Sendable {
    func title(for context: MomentNamingContext) async -> MomentTitle
    func title(forChapter context: ChapterNamingContext) async -> MomentTitle
}
