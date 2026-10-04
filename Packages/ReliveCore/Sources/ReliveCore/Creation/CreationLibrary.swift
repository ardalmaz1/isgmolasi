import Foundation

/// A calendar month.
public struct MonthKey: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0)
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// The first instant of the month.
    public func start(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }
}

/// A range of real capture dates.
public struct DateSpan: Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    /// The span covering the given dates, or nil when there are none.
    public init?(dates: [Date]) {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        self.init(start: first, end: last)
    }
}

/// The headline of a creation. Always taken from real data: a name the story already uses, or
/// the calendar month or year the creation covers.
public enum CreationTitle: Hashable, Sendable {
    /// A moment, trip or place name from the story ("Kaş", "December Evening").
    case named(String)
    case month(MonthKey)
    case year(Int)
}

/// Facts a creation may print. Each is nil when Relive doesn't actually know it — nothing is
/// guessed or invented.
public struct CreationFacts: Hashable, Sendable {
    public var title: CreationTitle?
    public var dateSpan: DateSpan?
    /// Only when every photo comes from the same named place.
    public var place: PlaceName?
    /// The place's coordinate, when the photos share one place and it has a location.
    public var coordinate: GeoCoordinate?

    public init(title: CreationTitle? = nil, dateSpan: DateSpan? = nil, place: PlaceName? = nil, coordinate: GeoCoordinate? = nil) {
        self.title = title
        self.dateSpan = dateSpan
        self.place = place
        self.coordinate = coordinate
    }

    public static let none = CreationFacts()
}

/// What a creation is made from. Codable so saved creations (Memory Books) remember it.
public enum CreationSource: Hashable, Sendable, Codable {
    case moment(MomentID)
    /// A trip: a chapter of consecutive moments away from home.
    case trip(UUID)
    case photos([AssetID])
    case month(MonthKey)
    case year(Int)
    /// Memories the user marked as favorites in Photos.
    case favorites
}

/// How many photos each kind of creation works with.
public enum CreationLimits {
    public static let collage = 2...12
    /// Photos preselected when a collage starts from a moment, month or year.
    public static let collagePreselection = 6
    public static let story = 3...10
}

/// A read-only view of the story for making things from it. Applies the same visibility rules
/// as the rest of the app (hidden moments and unavailable photos never appear) and adds the
/// creation rules: only still photos, never screenshots or receipts.
public struct CreationLibrary: Sendable {
    public var story: Story
    public var assets: [AssetID: MemoryAsset]
    public var userStates: [MomentID: MomentUserState]
    /// Photos that no longer resolve in the photo library.
    public var unavailableAssetIDs: Set<AssetID>
    public var calendar: Calendar
    public var scorer: AssetScorer
    /// Photos chosen straight from the photo library for a creation. They can be used like any
    /// other photo but are not part of the story: no moment, no trip, no place name.
    public private(set) var photoLibraryAssetIDs: Set<AssetID> = []

    public init(
        story: Story,
        assets: [AssetID: MemoryAsset],
        userStates: [MomentID: MomentUserState],
        unavailableAssetIDs: Set<AssetID>,
        calendar: Calendar,
        scorer: AssetScorer = AssetScorer()
    ) {
        self.story = story
        self.assets = assets
        self.userStates = userStates
        self.unavailableAssetIDs = unavailableAssetIDs
        self.calendar = calendar
        self.scorer = scorer
    }

    /// This library plus photos chosen from the photo library. A photo that is already a memory
    /// keeps its memory metadata; the others keep only their own.
    public func addingPhotoLibraryAssets(_ added: [MemoryAsset]) -> CreationLibrary {
        var library = self
        for asset in added where library.assets[asset.id] == nil {
            library.assets[asset.id] = asset
            library.photoLibraryAssetIDs.insert(asset.id)
        }
        return library
    }

    // MARK: - Creation assets

    /// Everything known about one photo, from the photo itself and the story it belongs to.
    public func creationAsset(_ id: AssetID) -> CreationAsset? {
        guard let asset = assets[id] else { return nil }
        let moment = photoLibraryAssetIDs.contains(id) ? nil : moment(containing: id)
        let chapter = moment.flatMap { story.chapter(for: $0) }
        return CreationAsset(
            asset: asset,
            source: photoLibraryAssetIDs.contains(id) ? .photoLibrary : .relive,
            place: moment.flatMap { $0.place ?? chapter?.place },
            momentID: moment?.id,
            tripID: chapter?.id
        )
    }

    /// What can truthfully be said about these photos together. A photo Relive knows nothing
    /// about counts as undated and unplaced.
    public func metadata(of photos: [AssetID]) -> CreationMetadataSummary {
        let known = photos.map { id in
            creationAsset(id) ?? CreationAsset(id: id, source: .photoLibrary, creationDate: nil)
        }
        return CreationMetadata.summarize(known, calendar: calendar)
    }

    // MARK: - Visibility

    public func isAvailable(_ id: AssetID) -> Bool {
        !unavailableAssetIDs.contains(id)
    }

    /// A photo that can go into a creation.
    public func isUsable(_ id: AssetID) -> Bool {
        guard isAvailable(id), let asset = assets[id] else { return false }
        return asset.kind == .photo && !asset.isScreenshot && asset.analysis?.isUtility != true
    }

    public func isVisible(_ moment: Moment) -> Bool {
        userStates[moment.id]?.isHidden != true && moment.assetIDs.contains(where: isAvailable)
    }

    /// Visible moments, chronological (undated last).
    public var visibleMoments: [Moment] {
        story.moments.filter(isVisible)
    }

    /// Usable photos of a moment, in the order they were taken. Collapsed near-duplicates are left out.
    public func usablePhotos(in moment: Moment) -> [AssetID] {
        moment.featuredAssetIDs.filter(isUsable)
    }

    /// The moment's cover if it is usable, otherwise its best usable photo.
    public func lead(of moment: Moment) -> AssetID? {
        let usable = usablePhotos(in: moment)
        if let hero = HeroSelector.resolvedHero(for: moment, userState: userStates[moment.id], isAvailable: isAvailable),
           usable.contains(hero) {
            return hero
        }
        return best(usable)
    }

    public func moment(containing id: AssetID) -> Moment? {
        story.moments.first { $0.assetIDs.contains(id) }
    }

    public func quality(_ id: AssetID) -> Double {
        assets[id].map { scorer.score($0) } ?? 0
    }

    /// The highest-scoring photo (earliest on ties).
    public func best(_ ids: [AssetID]) -> AssetID? {
        ids.min { lhs, rhs in
            let left = quality(lhs), right = quality(rhs)
            if abs(left - right) > 1e-9 { return left > right }
            return chronologicalOrder(lhs, rhs)
        }
    }

    /// Up to `count` photos spread over the whole set: the set is cut into `count` stretches of
    /// time and the best photo of each is taken. `include` (e.g. the cover) is always kept.
    /// Returned in the order they were taken.
    public func spreadPick(_ ids: [AssetID], count: Int, include: AssetID? = nil) -> [AssetID] {
        let ordered = ids.sorted(by: chronologicalOrder)
        guard count > 0 else { return [] }
        guard ordered.count > count else { return ordered }

        var picked: [AssetID] = []
        for bucket in 0..<count {
            let start = bucket * ordered.count / count
            let end = (bucket + 1) * ordered.count / count
            let slice = Array(ordered[start..<end])
            if let include, slice.contains(include) {
                picked.append(include)
            } else if let choice = best(slice) {
                picked.append(choice)
            }
        }
        return picked.sorted(by: chronologicalOrder)
    }

    public func chronologicalOrder(_ lhs: AssetID, _ rhs: AssetID) -> Bool {
        switch (assets[lhs]?.creationDate, assets[rhs]?.creationDate) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs < rhs
        }
    }

    // MARK: - Sources

    /// The photos a new creation starts with. For a moment, month or year this is a
    /// representative handful; for chosen photos it is those photos (still usable ones only).
    public func initialPhotos(for source: CreationSource, limit: Int) -> [AssetID] {
        switch source {
        case .photos(let ids):
            var seen = Set<AssetID>()
            return Array(ids.filter { isUsable($0) && seen.insert($0).inserted }.prefix(limit))
        case .moment(let id):
            guard let moment = story.moment(id: id), isVisible(moment) else { return [] }
            return spreadPick(usablePhotos(in: moment), count: limit, include: lead(of: moment))
        case .trip(let id):
            let summary = RecapSummary(moments: tripMoments(id), library: self)
            let interleaved = summary.interleave(summary.moments.map { summary.ranked($0) })
            return Array(interleaved.prefix(limit)).sorted(by: chronologicalOrder)
        case .month(let month):
            return MonthlyRecapBuilder(library: self).recap(for: month).highlights(limit: limit)
        case .year(let year):
            return YearInReviewBuilder(library: self).review(for: year).highlights(limit: limit)
        case .favorites:
            return spreadPick(favoritePhotos, count: limit)
        }
    }

    /// Usable photos marked as favorites, from visible moments, in the order they were taken.
    public var favoritePhotos: [AssetID] {
        visibleMoments.flatMap(usablePhotos(in:))
            .filter { assets[$0]?.isFavorite == true }
            .sorted(by: chronologicalOrder)
    }

    /// Everything usable a source can draw from (for "not enough photos" checks).
    public func availablePhotos(for source: CreationSource) -> [AssetID] {
        switch source {
        case .photos(let ids):
            return initialPhotos(for: .photos(ids), limit: ids.count)
        case .moment(let id):
            guard let moment = story.moment(id: id), isVisible(moment) else { return [] }
            return usablePhotos(in: moment)
        case .trip(let id):
            return tripMoments(id).flatMap(usablePhotos(in:))
        case .month(let month):
            return MonthlyRecapBuilder(library: self).recap(for: month).moments.flatMap(usablePhotos(in:))
        case .year(let year):
            return YearInReviewBuilder(library: self).review(for: year).moments.flatMap(usablePhotos(in:))
        case .favorites:
            return favoritePhotos
        }
    }

    /// The facts a creation from `source` may print, given the photos it actually uses.
    ///
    /// The source is only a hint: its name, month or year is used when *every* photo really
    /// belongs to it. A creation started from September that now holds August photos too is not
    /// "September" any more — it is described from its photos (`facts(forPhotos:)`).
    public func facts(for source: CreationSource, photos: [AssetID]) -> CreationFacts {
        let summary = metadata(of: photos)
        switch source {
        case .moment(let id):
            if let moment = story.moment(id: id), summary.momentID == moment.id {
                return facts(for: moment, photos: summary)
            }
        case .trip(let id):
            if let chapter = story.chapter(id: id), summary.tripID == chapter.id {
                var facts = facts(for: chapter)
                facts.dateSpan = summary.dateSpan
                return facts
            }
        case .month(let month):
            if CreationMetadata.fits(summary, month: month, calendar: calendar) {
                return CreationFacts(
                    title: .month(month),
                    dateSpan: summary.dateSpan,
                    place: summary.place,
                    coordinate: summary.place == nil ? nil : summary.coordinate
                )
            }
        case .year(let year):
            // "Our 2026" only for photos from several months of 2026; one month of it is that
            // month, not the year.
            if summary.period == .year(year) {
                return CreationFacts(title: .year(year), dateSpan: summary.dateSpan)
            }
        case .photos, .favorites:
            break
        }
        return facts(forPhotos: photos)
    }

    /// Visible moments of a trip, chronological.
    public func tripMoments(_ id: UUID) -> [Moment] {
        visibleMoments.filter { $0.chapterID == id }
    }

    /// Trips with at least one visible moment, newest first.
    public var visibleTrips: [Chapter] {
        let visible = Set(visibleMoments.compactMap(\.chapterID))
        return story.chapters.filter { visible.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    public func facts(for chapter: Chapter) -> CreationFacts {
        let title = chapter.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return CreationFacts(
            title: title.isEmpty ? chapter.place.map { .named($0.name) } : .named(title),
            dateSpan: DateSpan(start: chapter.startDate, end: chapter.endDate),
            place: chapter.place,
            coordinate: chapter.place == nil ? nil : chapter.centroid
        )
    }

    public func facts(for moment: Moment) -> CreationFacts {
        let chapter = story.chapter(for: moment)
        let place = moment.place ?? chapter?.place
        let span = moment.startDate.map { DateSpan(start: $0, end: moment.endDate ?? $0) }
        let title = moment.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        return CreationFacts(
            title: title.isEmpty ? place.map { .named($0.name) } : .named(title),
            dateSpan: span,
            place: place,
            coordinate: place == nil ? nil : (moment.centroid ?? chapter?.centroid)
        )
    }

    /// Facts for an arbitrary set of photos, derived from the photos themselves:
    /// - one moment → its name and place; one trip → the trip's;
    /// - otherwise one shared place → that place;
    /// - otherwise the calendar: one month ("September Together"), one year ("Our 2026");
    /// - several years, or photos without dates → no title (nothing true to say).
    /// Dates appear only when every photo has one.
    public func facts(forPhotos photos: [AssetID]) -> CreationFacts {
        guard !photos.isEmpty else { return .none }
        let summary = metadata(of: photos)
        if let id = summary.momentID, let moment = story.moment(id: id) {
            return facts(for: moment, photos: summary)
        }
        if let id = summary.tripID, let chapter = story.chapter(id: id) {
            var facts = facts(for: chapter)
            facts.dateSpan = summary.dateSpan
            return facts
        }
        return CreationFacts(
            title: summary.place.map { .named($0.name) } ?? CreationMetadata.periodTitle(for: summary),
            dateSpan: summary.dateSpan,
            place: summary.place,
            coordinate: summary.coordinate
        )
    }

    /// A moment's facts, dated by the photos actually used.
    private func facts(for moment: Moment, photos summary: CreationMetadataSummary) -> CreationFacts {
        var facts = facts(for: moment)
        facts.dateSpan = summary.dateSpan ?? facts.dateSpan
        return facts
    }

    public func dateSpan(of photos: [AssetID]) -> DateSpan? {
        DateSpan(dates: photos.compactMap { assets[$0]?.creationDate })
    }
}
