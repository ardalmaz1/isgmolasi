import Foundation

/// Where a photo in a creation comes from.
public enum CreationAssetSource: String, Hashable, Sendable, Codable {
    /// A memory in the Relive story.
    case relive
    /// Chosen straight from the iPhone photo library for one creation. Never added to the story.
    case photoLibrary
}

/// Everything Relive knows about one photo in a creation.
///
/// **Metadata follows the photo.** Every value here comes from the photo itself (and, for a
/// memory, from the moment and trip it belongs to) — never from the screen, the month or the
/// request a creation was started from. Anything unknown stays nil.
public struct CreationAsset: Hashable, Sendable, Identifiable {
    public var id: AssetID
    public var source: CreationAssetSource
    /// The capture date the photo library reports.
    public var creationDate: Date?
    /// Where the photo was taken, from its own location data.
    public var coordinate: GeoCoordinate?
    /// A place name Relive already knows for this photo: its moment's (or trip's) place. Never
    /// looked up for a creation, so photos from outside the story have none.
    public var place: PlaceName?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isFavorite: Bool
    /// The moment it belongs to, for memories.
    public var momentID: MomentID?
    /// The trip (chapter) its moment belongs to.
    public var tripID: UUID?

    public init(
        id: AssetID,
        source: CreationAssetSource,
        creationDate: Date?,
        coordinate: GeoCoordinate? = nil,
        place: PlaceName? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        isFavorite: Bool = false,
        momentID: MomentID? = nil,
        tripID: UUID? = nil
    ) {
        self.id = id
        self.source = source
        self.creationDate = creationDate
        self.coordinate = coordinate?.isValid == true ? coordinate : nil
        self.place = place
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.momentID = momentID
        self.tripID = tripID
    }

    /// From a photo-library snapshot. Only the photo's own metadata is kept.
    public init(asset: MemoryAsset, source: CreationAssetSource, place: PlaceName? = nil, momentID: MomentID? = nil, tripID: UUID? = nil) {
        self.init(
            id: asset.id,
            source: source,
            creationDate: asset.creationDate,
            coordinate: asset.location,
            place: place,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            momentID: momentID,
            tripID: tripID
        )
    }

    /// Width over height, or nil when the size isn't known.
    public var aspectRatio: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    /// Nil when the size isn't known.
    public var orientation: PhotoOrientation? {
        aspectRatio.map(PhotoOrientation.init(aspectRatio:))
    }
}

/// The period a set of photos covers, from their own capture dates.
public enum CreationPeriod: Hashable, Sendable {
    /// Every photo was taken on this day (the start of the day).
    case day(Date)
    /// Every photo was taken in this month, on more than one day.
    case month(MonthKey)
    /// Every photo was taken in this year, across more than one month.
    case year(Int)
    /// The photos span several years.
    case years(first: Int, last: Int)
}

/// What can truthfully be said about a set of photos as a whole.
public struct CreationMetadataSummary: Hashable, Sendable {
    public var count: Int
    /// Photos with a capture date.
    public var datedCount: Int
    /// Only when every photo has a capture date — otherwise the span would claim more than
    /// Relive knows.
    public var dateSpan: DateSpan?
    /// Only when every photo has a capture date.
    public var period: CreationPeriod?
    /// Only when every photo has the same known place.
    public var place: PlaceName?
    /// Only when every photo has a location and they were all taken close together.
    public var coordinate: GeoCoordinate?
    /// When every photo belongs to the same moment.
    public var momentID: MomentID?
    /// When every photo belongs to the same trip.
    public var tripID: UUID?

    public var isEmpty: Bool { count == 0 }
}

/// Deterministic rules for describing a selection of photos. Pure functions, tested directly.
public enum CreationMetadata {
    /// Photos within this distance (metres) of their centre count as taken in one place.
    public static let sameLocationRadius: Double = 1_000

    public static func summarize(_ assets: [CreationAsset], calendar: Calendar) -> CreationMetadataSummary {
        let dates = assets.compactMap(\.creationDate)
        let allDated = !assets.isEmpty && dates.count == assets.count
        let span = allDated ? DateSpan(dates: dates) : nil

        var summary = CreationMetadataSummary(count: assets.count, datedCount: dates.count)
        summary.dateSpan = span
        summary.period = span.map { period(of: $0, calendar: calendar) }

        // One place only when every photo has the same known place.
        if let first = assets.first?.place,
           assets.allSatisfy({ $0.place?.comparisonKey == first.comparisonKey }) {
            summary.place = first
        }

        // One location only when every photo has one and they're close together.
        let coordinates = assets.compactMap(\.coordinate)
        if !assets.isEmpty, coordinates.count == assets.count,
           let centre = GeoCoordinate.centroid(of: coordinates),
           coordinates.allSatisfy({ $0.distance(to: centre) <= sameLocationRadius }) {
            summary.coordinate = centre
        }

        if let first = assets.first?.momentID, assets.allSatisfy({ $0.momentID == first }) {
            summary.momentID = first
        }
        if let first = assets.first?.tripID, assets.allSatisfy({ $0.tripID == first }) {
            summary.tripID = first
        }
        return summary
    }

    /// The narrowest calendar period that contains the whole span.
    public static func period(of span: DateSpan, calendar: Calendar) -> CreationPeriod {
        if calendar.isDate(span.start, inSameDayAs: span.end) {
            return .day(calendar.startOfDay(for: span.start))
        }
        let start = MonthKey(date: span.start, calendar: calendar)
        let end = MonthKey(date: span.end, calendar: calendar)
        if start == end { return .month(start) }
        if start.year == end.year { return .year(start.year) }
        return .years(first: start.year, last: end.year)
    }

    /// A headline from the period alone, for photos that share no name or place: one month →
    /// that month; one year (several months) → that year. One day, several years or unknown
    /// dates get none — the date line (or a neutral headline chosen by the app) says it.
    public static func periodTitle(for summary: CreationMetadataSummary) -> CreationTitle? {
        switch summary.period {
        case .month(let month): return .month(month)
        case .year(let year): return .year(year)
        case .day, .years, nil: return nil
        }
    }

    /// Whether the photos all fall inside `month`.
    public static func fits(_ summary: CreationMetadataSummary, month: MonthKey, calendar: Calendar) -> Bool {
        switch summary.period {
        case .day(let day): return MonthKey(date: day, calendar: calendar) == month
        case .month(let key): return key == month
        default: return false
        }
    }

    /// Whether the photos all fall inside `year`.
    public static func fits(_ summary: CreationMetadataSummary, year: Int, calendar: Calendar) -> Bool {
        switch summary.period {
        case .day(let day): return calendar.component(.year, from: day) == year
        case .month(let key): return key.year == year
        case .year(let key): return key == year
        default: return false
        }
    }
}
