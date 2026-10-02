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
        }
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
        }
    }

    /// The facts a creation from `source` may print, given the photos it actually uses.
    public func facts(for source: CreationSource, photos: [AssetID]) -> CreationFacts {
        switch source {
        case .moment(let id):
            if let moment = story.moment(id: id), Set(photos).isSubset(of: Set(moment.assetIDs)) {
                return facts(for: moment)
            }
            return facts(forPhotos: photos)
        case .photos:
            return facts(forPhotos: photos)
        case .trip(let id):
            guard let chapter = story.chapter(id: id) else { return facts(forPhotos: photos) }
            var facts = facts(for: chapter)
            facts.dateSpan = dateSpan(of: photos) ?? facts.dateSpan
            return facts
        case .month(let month):
            let recap = MonthlyRecapBuilder(library: self).recap(for: month)
            var facts = sharedPlaceFacts(recap.moments)
            facts.title = .month(month)
            facts.dateSpan = dateSpan(of: photos) ?? recap.dateSpan
            return facts
        case .year(let year):
            let review = YearInReviewBuilder(library: self).review(for: year)
            return CreationFacts(title: .year(year), dateSpan: dateSpan(of: photos) ?? review.dateSpan)
        }
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

    /// Facts for an arbitrary set of photos. A title only when they share one moment, one trip
    /// or one place; the dates are the photos' own.
    public func facts(forPhotos photos: [AssetID]) -> CreationFacts {
        let span = dateSpan(of: photos)
        let owners = photos.map { moment(containing: $0) }
        guard !photos.isEmpty, owners.allSatisfy({ $0 != nil }) else {
            return CreationFacts(dateSpan: span)
        }
        var moments: [Moment] = []
        for case let owner? in owners where !moments.contains(where: { $0.id == owner.id }) {
            moments.append(owner)
        }
        if moments.count == 1, let only = moments.first {
            var facts = facts(for: only)
            facts.dateSpan = span ?? facts.dateSpan
            return facts
        }
        if let chapterID = moments.first?.chapterID, moments.allSatisfy({ $0.chapterID == chapterID }),
           let chapter = story.chapter(id: chapterID) {
            var facts = facts(for: chapter)
            facts.dateSpan = span
            return facts
        }
        var facts = sharedPlaceFacts(moments)
        facts.dateSpan = span
        if let place = facts.place { facts.title = .named(place.name) }
        return facts
    }

    /// Place facts when every moment has the same named place.
    func sharedPlaceFacts(_ moments: [Moment]) -> CreationFacts {
        let places = moments.map { $0.place ?? story.chapter(for: $0)?.place }
        guard let first = places.first.flatMap({ $0 }),
              places.allSatisfy({ $0?.comparisonKey == first.comparisonKey }) else {
            return CreationFacts()
        }
        let coordinates = moments.compactMap(\.centroid)
        return CreationFacts(place: first, coordinate: GeoCoordinate.centroid(of: coordinates))
    }

    public func dateSpan(of photos: [AssetID]) -> DateSpan? {
        DateSpan(dates: photos.compactMap { assets[$0]?.creationDate })
    }
}
