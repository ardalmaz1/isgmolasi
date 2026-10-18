import Foundation

/// A calendar day, in the library's calendar.
public struct DayKey: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public var monthKey: MonthKey { MonthKey(year: year, month: month) }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Everything the intelligence layer may use about one memory — signals Relive already has,
/// normalized. Nothing here is guessed: an unknown date, place or quality stays unknown.
///
/// Built from the story (`MemoryCandidate.build`), never from pixels. The internal
/// `suitability` is never shown to anyone.
public struct MemoryCandidate: Hashable, Sendable, Codable, Identifiable {
    public var id: AssetID { assetID }

    public var assetID: AssetID
    /// The capture date the photo library reports; nil when unknown.
    public var captureDate: Date?
    public var day: DayKey?
    public var month: MonthKey?
    /// The photo has its own location data.
    public var hasLocation: Bool
    /// A place name Relive already knows for this photo (its moment's or trip's).
    public var place: PlaceName?
    public var momentID: MomentID?
    public var tripID: UUID?
    public var kind: MediaKind
    /// Nil when the size isn't known.
    public var orientation: PhotoOrientation?
    /// Favorited in Relive.
    public var isFavorite: Bool
    /// Marked as a favorite in the Photos app.
    public var isPhotosFavorite: Bool
    /// The cover its moment shows (the user's choice, or Relive's).
    public var isMomentCover: Bool
    /// The cover the user chose for its moment.
    public var isUserCover: Bool
    /// A re-saved copy of another memory (e.g. a WhatsApp copy).
    public var isDuplicateCopy: Bool
    /// Collapsed behind "Show similar" in its moment.
    public var isCollapsedSimilar: Bool
    /// Its moment is hidden.
    public var isHidden: Bool
    /// The couple asked Relive not to suggest it. Like a hidden memory for automatic choices;
    /// a photo the user picks by hand is still used.
    public var isExcludedFromSuggestions: Bool = false
    /// Still in the photo library.
    public var isAvailable: Bool
    /// A still photo that can go into a creation (not a video, screenshot or receipt).
    public var isUsable: Bool
    /// Faces found by on-device analysis; nil when analysis didn't run or failed.
    public var faceCount: Int?
    /// On-device analysis ran and could see the image.
    public var hasAnalysis: Bool
    /// Position in the order the memories were taken (undated last).
    public var captureIndex: Int
    /// How good the photo is as an image (`AssetScorer`, which already counts the Photos
    /// favorite, faces, sharpness, aesthetics and screenshot/utility penalties). Internal only.
    var quality: Double

    /// Whether it may appear in an automatic creation at all.
    public var isEligible: Bool {
        isAvailable && isUsable && !isHidden && !isExcludedFromSuggestions && !isDuplicateCopy
    }

    /// People in the picture vs. a scene — only when analysis knows.
    public var framing: Framing? {
        guard let faceCount else { return nil }
        return faceCount > 0 ? .people : .scene
    }

    public enum Framing: String, Hashable, Sendable, Codable {
        case people
        case scene
    }
}

extension MemoryCandidate {
    /// Candidates for `ids` (order and duplicates of the input don't matter), from what the
    /// library knows. Photos the library knows nothing about are returned as unavailable.
    public static func build(_ ids: [AssetID], library: CreationLibrary) -> [MemoryCandidate] {
        var seen = Set<AssetID>()
        let unique = ids.filter { seen.insert($0).inserted }
        let ordered = unique.sorted(by: library.chronologicalOrder)
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })

        // One pass over the story: which moment holds each photo, and what it says about it.
        var momentOf: [AssetID: Moment] = [:]
        if !library.story.moments.isEmpty {
            let wanted = Set(unique)
            for moment in library.story.moments {
                for id in moment.assetIDs where wanted.contains(id) && momentOf[id] == nil {
                    momentOf[id] = moment
                }
            }
        }

        return unique.map { id in
            let asset = library.assets[id]
            let fromLibrary = library.photoLibraryAssetIDs.contains(id)
            let moment = fromLibrary ? nil : momentOf[id]
            let chapter = moment.flatMap { library.story.chapter(for: $0) }
            let state = moment.flatMap { library.userStates[$0.id] }
            let cover = moment.flatMap { HeroSelector.resolvedHero(for: $0, userState: state, isAvailable: library.isAvailable) }
            let analysis = asset?.analysis
            let analysisSees = analysis.map { !$0.failures.contains(.thumbnailUnavailable) } ?? false
            let facesKnown = analysisSees && analysis?.failures.contains(.faceDetection) == false
            let date = asset?.creationDate
            return MemoryCandidate(
                assetID: id,
                captureDate: date,
                day: date.map { DayKey(date: $0, calendar: library.calendar) },
                month: date.map { MonthKey(date: $0, calendar: library.calendar) },
                hasLocation: asset?.location?.isValid == true,
                place: moment.flatMap { $0.place ?? chapter?.place },
                momentID: moment?.id,
                tripID: chapter?.id,
                kind: asset?.kind ?? .photo,
                orientation: asset?.aspectRatio.map(PhotoOrientation.init(aspectRatio:)),
                isFavorite: library.favoriteAssetIDs.contains(id),
                isPhotosFavorite: asset?.isFavorite ?? false,
                isMomentCover: cover == id,
                isUserCover: state?.heroOverrideAssetID == id,
                isDuplicateCopy: moment?.duplicateAssetIDs.contains(id) ?? false,
                isCollapsedSimilar: moment.map { $0.similarAssetIDs.contains(id) && !$0.featuredAssetIDs.contains(id) } ?? false,
                isHidden: moment.map { library.userStates[$0.id]?.isHidden == true } ?? false,
                isExcludedFromSuggestions: library.suggestionExcludedAssetIDs.contains(id),
                isAvailable: asset != nil && library.isAvailable(id),
                isUsable: library.isUsable(id),
                faceCount: facesKnown ? analysis?.faceCount : nil,
                hasAnalysis: analysisSees,
                captureIndex: rank[id] ?? 0,
                quality: asset.map { library.scorer.score($0) } ?? 0
            )
        }
    }
}

extension PhotoOrientation: Codable {}
