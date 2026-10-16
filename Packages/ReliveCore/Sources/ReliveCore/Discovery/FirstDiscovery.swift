import Foundation

/// What Relive shows first after a new story is built — "We found something for you." — chosen
/// from what the existing systems already know (Made for You, trips, recaps, moments). No new
/// recommendation logic: Made for You decides what is worth making; this only picks which of
/// its results (or, failing that, which moment) to put first.
///
/// Hierarchy:
/// 1. a trip offered as a Memory Movie (Made for You's own movie suggestion),
/// 2. a Monthly Recap / Our Year, or another Made for You suggestion,
/// 3. the strongest moment (several photos),
/// 4. a small story: its best moment, however small — "Your story has started."
public struct FirstDiscovery: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case movie
        case recap
        case suggestion
        case moment
        case smallStory
    }

    public var kind: Kind
    /// The Made for You suggestion it opens (movie, recap, suggestion).
    public var suggestion: MadeForYouSuggestion?
    /// The moment it shows (moment, small story).
    public var momentID: MomentID?
    /// The photo it leads with.
    public var coverAssetID: AssetID?

    public init(kind: Kind, suggestion: MadeForYouSuggestion? = nil, momentID: MomentID? = nil, coverAssetID: AssetID? = nil) {
        self.kind = kind
        self.suggestion = suggestion
        self.momentID = momentID
        self.coverAssetID = coverAssetID
    }
}

public struct FirstDiscoveryResolver: Sendable {
    /// A moment with at least this many usable photos is a strong first result on its own.
    public var strongMomentPhotos: Int

    public init(strongMomentPhotos: Int = 4) {
        self.strongMomentPhotos = strongMomentPhotos
    }

    /// - Parameters:
    ///   - suggestions: Made for You's current suggestions, best first.
    ///   - library: the new story.
    public func resolve(suggestions: [MadeForYouSuggestion], library: CreationLibrary) -> FirstDiscovery? {
        if let movie = suggestions.first(where: { $0.creation == .movie }) {
            return FirstDiscovery(kind: .movie, suggestion: movie, coverAssetID: movie.coverAssetID)
        }
        if let recap = suggestions.first(where: { $0.creation == .monthlyRecap || $0.creation == .yearInReview }) {
            return FirstDiscovery(kind: .recap, suggestion: recap, coverAssetID: recap.coverAssetID)
        }
        if let other = suggestions.first {
            return FirstDiscovery(kind: .suggestion, suggestion: other, coverAssetID: other.coverAssetID)
        }
        let ranked = library.visibleMoments
            .map { (moment: $0, photos: library.usablePhotos(in: $0)) }
            .filter { !$0.photos.isEmpty }
            .sorted { lhs, rhs in
                if lhs.photos.count != rhs.photos.count { return lhs.photos.count > rhs.photos.count }
                return lhs.moment.sortDate > rhs.moment.sortDate
            }
        guard let best = ranked.first else { return nil }
        let cover = best.moment.heroAssetID.flatMap { best.photos.contains($0) ? $0 : nil } ?? best.photos.first
        let kind: FirstDiscovery.Kind = best.photos.count >= strongMomentPhotos ? .moment : .smallStory
        return FirstDiscovery(kind: kind, momentID: best.moment.id, coverAssetID: cover)
    }
}
