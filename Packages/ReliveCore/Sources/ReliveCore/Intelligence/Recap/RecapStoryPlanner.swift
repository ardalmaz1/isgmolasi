import Foundation

/// The period a recap covers.
public enum RecapPeriod: Hashable, Sendable, Codable {
    case month(MonthKey)
    case year(Int)

    public var source: CreationSource {
        switch self {
        case .month(let month): .month(month)
        case .year(let year): .year(year)
        }
    }
}

/// Facts about a period, every one counted from the story (`TemporalIndex`, the recap builders).
/// A fact that isn't clearly true — a tie for "most", a place nobody named — is nil.
public struct RecapInsights: Hashable, Sendable, Codable {
    public struct PlaceCount: Hashable, Sendable, Codable {
        public var place: PlaceName
        public var moments: Int
        public var days: Int
    }

    public var period: RecapPeriod
    public var memoryCount: Int
    public var momentCount: Int
    /// Distinct days with at least one memory.
    public var activeDays: Int
    /// Known places, in the order they first appear.
    public var places: [PlaceName]
    public var tripCount: Int
    public var favoriteCount: Int
    public var monthsRepresented: [MonthKey]
    /// The month with strictly the most memories (years only; nil on a tie).
    public var mostRepresentedMonth: MonthKey?
    /// The place with strictly the most moments, on at least two days (nil on a tie).
    public var mostRepresentedPlace: PlaceCount?
    public var earliest: Date?
    public var latest: Date?
    /// The longest trip in the period, in days of memories inside the period.
    public var longestTripDays: Int?
}

/// One chapter of a recap: a few true words, the photos that show it, optional rows.
public struct RecapChapter: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case opening, firstMemory, tripHighlight, placeHighlight, dayHighlight, peopleGallery
        case favoriteHighlight, visualGrid, places, timeline, numbers, monthByMonth, compactSummary, closing
    }

    /// A row: a month, a place, a date on the timeline, a number.
    public struct Entry: Hashable, Sendable, Codable {
        public var title: String
        public var detail: String?
        public var photo: AssetID?
        public var momentID: MomentID?
        public var month: MonthKey?
    }

    public var id: String
    public var kind: Kind
    public var text: EditorialText
    /// The structured facts the text was made from (what a future AI provider would receive).
    public var facts: EditorialFacts
    public var hero: AssetID?
    public var photos: [AssetID]
    public var entries: [Entry]
    public var momentID: MomentID?
    public var tripID: UUID?
}

/// A recap, ready to show: rich (chapters) or compact (a sparse period, never padded).
public struct RecapPlan: Hashable, Sendable, Codable {
    public var period: RecapPeriod
    public var isRich: Bool
    public var insights: RecapInsights
    public var chapters: [RecapChapter]
    /// Where "Make Collage / Create Story / Make Memory Book" start: the period itself, so every
    /// photo comes from Memory Intelligence's selection for it.
    public var creationSource: CreationSource { period.source }
    /// Photos of the share card (the plan's best, diverse).
    public var sharePhotos: [AssetID]
    var collapsedSimilar: Int
    var duplicatesRemoved: Int

    /// DEBUG line: counts and kinds only.
    public var diagnosticsLine: String {
        let code: String = switch period {
        case .month(let month): "\(month.year)-\(month.month < 10 ? "0" : "")\(month.month)"
        case .year(let year): "\(year)"
        }
        return "recap_plan period=\(code) rich=\(isRich) memories=\(insights.memoryCount) chapters=\(chapters.count)"
            + " chapterKinds=[\(chapters.map(\.kind.rawValue).joined(separator: ","))] placesKnown=\(insights.places.count)"
            + " duplicatesRemoved=\(duplicatesRemoved) similarCollapsed=\(collapsedSimilar)"
    }
}

/// Plans a recap as a sequence of editorial chapters that adapt to what the period really holds.
/// Every photo comes from Memory Intelligence; every sentence from `EditorialFacts`; a weak
/// chapter simply isn't there, and a sparse period gets one honest compact page.
public struct RecapStoryPlanner: Sendable {
    public var library: CreationLibrary
    public var text: any EditorialTextProviding
    public var locale: Locale
    /// Rich recaps keep at most this many chapters (months, years).
    public static let monthChapterLimit = 10
    public static let yearChapterLimit = 16
    /// A rich month needs at least this many memories (and a sufficient recap).
    public static let richMonthMinimum = 8
    /// A rich recap that finds fewer true chapters than this (opening and closing included) is
    /// told as one compact page instead: never padded to look bigger than it was.
    public static let monthChapterMinimum = 5
    public static let yearChapterMinimum = 5

    public init(library: CreationLibrary, text: any EditorialTextProviding = DeterministicEditorialTextProvider(), locale: Locale = .reliveDisplay) {
        self.library = library
        self.text = text
        self.locale = locale
    }

    private var calendar: Calendar { library.calendar }
    private var engine: MemoryIntelligenceEngine { MemoryIntelligenceEngine(library: library, locale: locale).quiet }
    private var names: MonthNames { MonthNames(locale: locale, calendar: calendar) }

    // MARK: - Planning

    public func plan(_ period: RecapPeriod) -> RecapPlan {
        let index = TemporalIndex(library: library)
        let entries: [TemporalIndex.Entry]
        let moments: [Moment]
        let trips: [Chapter]
        var sufficient: Bool
        switch period {
        case .month(let month):
            let recap = MonthlyRecapBuilder(library: library).recap(for: month, index: index)
            entries = index.entries(in: month)
            moments = recap.moments
            trips = recap.chapters
            sufficient = recap.isSufficient && recap.statistics.memoryCount >= Self.richMonthMinimum
        case .year(let year):
            let review = YearInReviewBuilder(library: library).review(for: year, index: index)
            entries = index.entries(inYear: year)
            moments = review.moments
            trips = review.chapters
            sufficient = review.isSufficient
        }
        let usable = entries.map(\.assetID).filter(library.isUsable)
        let insights = insights(period: period, entries: entries, moments: moments, trips: trips)
        let overview = engine.plan(IntelligenceRequest(pool: usable, target: .general(limit: period.isYear ? 12 : 9), minimum: 1))

        var builder = Chapters(planner: self, insights: insights, period: period)
        if !sufficient {
            builder.compact(photos: overview.selected)
        } else {
            builder.opening(lead: overview.lead, photos: overview.selected)
            builder.firstMemory(entries: entries, moments: moments)
            if period.isYear {
                builder.numbers()
                builder.monthByMonth(entries: entries, moments: moments, trips: trips)
            }
            builder.trips(trips, moments: moments, limit: period.isYear ? 2 : 1)
            builder.repeatedPlace(moments: moments)
            builder.busyDay(entries: entries, moments: moments)
            builder.people(usable: usable)
            builder.favorites(usable: usable)
            builder.frames(overview.selected)
            builder.places(moments: moments)
            if !period.isYear { builder.timeline(moments: moments) }
            builder.closing(photos: overview.selected)
            builder.trim(to: period.isYear ? Self.yearChapterLimit : Self.monthChapterLimit)
            if builder.chapters.count < (period.isYear ? Self.yearChapterMinimum : Self.monthChapterMinimum) {
                sufficient = false
                builder = Chapters(planner: self, insights: insights, period: period)
                builder.compact(photos: overview.selected)
            }
        }

        return RecapPlan(
            period: period,
            isRich: sufficient,
            insights: insights,
            chapters: builder.chapters,
            sharePhotos: Array(overview.selected.prefix(6)),
            collapsedSimilar: overview.collapsedSimilar.count,
            duplicatesRemoved: overview.excludedDuplicates.count
        )
    }

    // MARK: - Insights

    func insights(period: RecapPeriod, entries: [TemporalIndex.Entry], moments: [Moment], trips: [Chapter]) -> RecapInsights {
        let days = Set(entries.map { DayKey(date: $0.date, calendar: calendar) })
        var places: [PlaceName] = []
        var placeMoments: [String: (PlaceName, Set<MomentID>, Set<DayKey>)] = [:]
        let entriesByMoment = Dictionary(grouping: entries, by: \.momentID)
        for moment in moments {
            guard let place = place(of: moment) else { continue }
            if !places.contains(where: { $0.comparisonKey == place.comparisonKey }) { places.append(place) }
            var record = placeMoments[place.comparisonKey] ?? (place, [], [])
            record.1.insert(moment.id)
            for entry in entriesByMoment[moment.id] ?? [] { record.2.insert(DayKey(date: entry.date, calendar: calendar)) }
            placeMoments[place.comparisonKey] = record
        }
        let placeRanking = placeMoments.values.sorted { $0.1.count > $1.1.count }
        var mostPlace: RecapInsights.PlaceCount?
        if let top = placeRanking.first, top.1.count >= 2, top.2.count >= 2,
           placeRanking.count == 1 || placeRanking[1].1.count < top.1.count {
            mostPlace = .init(place: top.0, moments: top.1.count, days: top.2.count)
        }

        let byMonth = Dictionary(grouping: entries, by: \.month).mapValues(\.count)
        var mostMonth: MonthKey?
        if case .year = period, byMonth.count > 1 {
            let sorted = byMonth.sorted { $0.value > $1.value }
            if sorted[0].value > sorted[1].value { mostMonth = sorted[0].key }
        }

        let tripDays = trips.map { trip in
            Set(entries.filter { entry in moments.first { $0.id == entry.momentID }?.chapterID == trip.id }
                .map { DayKey(date: $0.date, calendar: calendar) }).count
        }
        let usable = entries.map(\.assetID).filter(library.isUsable)
        let statistics = StoryStatistics.compute(
            story: Story(generatedAt: library.story.generatedAt, moments: moments, chapters: trips),
            assets: library.assets, userStates: library.userStates, isAvailable: library.isAvailable
        )
        return RecapInsights(
            period: period,
            memoryCount: statistics.memoryCount,
            momentCount: moments.count,
            activeDays: days.count,
            places: places,
            tripCount: trips.count,
            favoriteCount: usable.filter(library.favoriteAssetIDs.contains).count,
            monthsRepresented: byMonth.keys.sorted(),
            mostRepresentedMonth: mostMonth,
            mostRepresentedPlace: mostPlace,
            earliest: entries.map(\.date).min(),
            latest: entries.map(\.date).max(),
            longestTripDays: tripDays.max()
        )
    }

    func place(of moment: Moment) -> PlaceName? {
        moment.place ?? library.story.chapter(for: moment)?.place
    }

    func periodName(_ period: RecapPeriod) -> String {
        switch period {
        case .month(let month): names.full(month.month)
        case .year(let year): String(year)
        }
    }

    func dayLabel(_ day: DayKey, withYear: Bool = false) -> String {
        withYear ? "\(names.full(day.month)) \(day.day), \(day.year)" : "\(names.full(day.month)) \(day.day)"
    }

    // MARK: - Chapters

    /// Adds chapters in order, never repeating a hero photo or a fact.
    struct Chapters {
        let planner: RecapStoryPlanner
        let insights: RecapInsights
        let period: RecapPeriod
        var chapters: [RecapChapter] = []
        var usedHeroes = Set<AssetID>()
        var toldPlaces = Set<String>()
        var toldDays = Set<DayKey>()

        private var calendar: Calendar { planner.calendar }
        private var isYear: Bool { period.isYear }
        private var name: String { planner.periodName(period) }

        /// The best photo among `ids` that hasn't led a chapter yet.
        mutating func hero(_ ids: [AssetID]) -> AssetID? {
            let ranked = planner.engine.rankedLeads(ids.filter(planner.library.isUsable), target: .general(limit: 1))
            guard let pick = ranked.first(where: { !usedHeroes.contains($0) }) else { return nil }
            usedHeroes.insert(pick)
            return pick
        }

        mutating func add(_ kind: RecapChapter.Kind, facts: EditorialFacts, hero: AssetID?, photos: [AssetID] = [], entries: [RecapChapter.Entry] = [], momentID: MomentID? = nil, tripID: UUID? = nil) {
            chapters.append(RecapChapter(
                id: "\(kind.rawValue)-\(chapters.count)",
                kind: kind,
                text: planner.text.text(for: facts),
                facts: facts,
                hero: hero,
                photos: photos,
                entries: entries,
                momentID: momentID,
                tripID: tripID
            ))
        }

        mutating func compact(photos: [AssetID]) {
            add(.compactSummary,
                facts: .compact(periodName: name, isYear: isYear, memories: insights.memoryCount, moments: insights.momentCount),
                hero: hero(photos), photos: photos)
        }

        mutating func opening(lead: AssetID?, photos: [AssetID]) {
            var heroID = lead
            if let lead { usedHeroes.insert(lead) } else { heroID = hero(photos) }
            switch period {
            case .month(let month):
                add(.opening, facts: .monthOpening(monthName: name, year: month.year, memories: insights.memoryCount, moments: insights.momentCount, places: insights.places.count), hero: heroID)
            case .year(let year):
                add(.opening, facts: .yearOpening(year: year, memories: insights.memoryCount, moments: insights.momentCount, months: insights.monthsRepresented.count), hero: heroID)
            }
        }

        /// The earliest memory — only when there's a "rest" to begin (more than one day).
        mutating func firstMemory(entries: [TemporalIndex.Entry], moments: [Moment]) {
            guard insights.activeDays >= 2, let first = entries.min(by: { ($0.date, $0.assetID) < ($1.date, $1.assetID) }),
                  planner.library.isUsable(first.assetID), let moment = moments.first(where: { $0.id == first.momentID }) else { return }
            let day = DayKey(date: first.date, calendar: calendar)
            toldDays.insert(day)
            let place = planner.place(of: moment)
            usedHeroes.insert(first.assetID)
            add(.firstMemory,
                facts: .firstMemory(periodName: name, isYear: isYear, dateLabel: planner.dayLabel(day), place: place?.name),
                hero: first.assetID, momentID: moment.id)
        }

        mutating func numbers() {
            guard case .year(let year) = period else { return }
            var rows: [RecapChapter.Entry] = [
                .init(title: "\(insights.memoryCount)", detail: insights.memoryCount == 1 ? "memory" : "memories"),
                .init(title: "\(insights.momentCount)", detail: insights.momentCount == 1 ? "moment" : "moments"),
                .init(title: "\(insights.activeDays)", detail: insights.activeDays == 1 ? "day with memories" : "days with memories"),
            ]
            if !insights.places.isEmpty { rows.append(.init(title: "\(insights.places.count)", detail: insights.places.count == 1 ? "place" : "places")) }
            if insights.tripCount > 0 { rows.append(.init(title: "\(insights.tripCount)", detail: insights.tripCount == 1 ? "trip" : "trips")) }
            add(.numbers, facts: .numbers(year: year), hero: nil, entries: rows)
        }

        /// One row per month that has memories, in order — never an empty month.
        mutating func monthByMonth(entries: [TemporalIndex.Entry], moments: [Moment], trips: [Chapter]) {
            guard case .year(let year) = period, insights.monthsRepresented.count >= 2 else { return }
            let byMonth = Dictionary(grouping: entries, by: \.month)
            let rows = insights.monthsRepresented.map { month -> RecapChapter.Entry in
                let ids = (byMonth[month] ?? []).map(\.assetID).filter(planner.library.isUsable)
                let monthMoments = Set((byMonth[month] ?? []).map(\.momentID))
                let trip = trips.first { trip in moments.contains { monthMoments.contains($0.id) && $0.chapterID == trip.id } }
                let places = Set(moments.filter { monthMoments.contains($0.id) }.compactMap { planner.place(of: $0)?.comparisonKey })
                let onePlace = places.count == 1 ? moments.first { monthMoments.contains($0.id) }.flatMap(planner.place(of:))?.name : nil
                let detail = [DeterministicEditorialTextProvider.count(byMonth[month]?.count ?? 0, "memory", "memories"),
                              trip.map { $0.title.primary.isEmpty ? ($0.place?.name ?? "") : $0.title.primary } ?? onePlace]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return .init(title: planner.names.full(month.month), detail: detail,
                             photo: planner.engine.rankedLeads(ids, target: .general(limit: 1)).first, month: month)
            }
            add(.monthByMonth, facts: .monthByMonth(year: year, months: rows.count), hero: nil, entries: rows)
        }

        /// The period's trips (the story's own chapters), biggest first.
        mutating func trips(_ trips: [Chapter], moments: [Moment], limit: Int) {
            var ranked: [(trip: Chapter, photos: [AssetID])] = []
            for trip in trips {
                let tripMoments: [Moment] = moments.filter { $0.chapterID == trip.id }
                let photos: [AssetID] = tripMoments.flatMap { planner.library.usablePhotos(in: $0) }
                if photos.count >= 4 { ranked.append((trip, photos)) }
            }
            ranked.sort { lhs, rhs in
                if lhs.photos.count != rhs.photos.count { return lhs.photos.count > rhs.photos.count }
                return lhs.trip.startDate < rhs.trip.startDate
            }
            for (trip, photos) in ranked.prefix(limit) {
                let candidates = MemoryCandidate.build(photos, library: planner.library)
                let days = Set(candidates.compactMap(\.day)).count
                let plan = planner.engine.plan(IntelligenceRequest(pool: photos, target: .general(limit: 6), minimum: 1))
                let title = trip.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let name = title.isEmpty ? trip.place?.name : title else { continue }
                let date = PeriodDescriptor(candidates: candidates).label(locale: planner.locale, calendar: calendar)
                if let place = trip.place { toldPlaces.insert(place.comparisonKey) }
                add(.tripHighlight,
                    facts: .trip(name: name, days: days, memories: photos.count, dateLabel: date),
                    hero: hero(plan.selected), photos: plan.selected, tripID: trip.id)
            }
        }

        /// A known place on several days — unless a trip chapter already told it.
        mutating func repeatedPlace(moments: [Moment]) {
            guard let top = insights.mostRepresentedPlace, !toldPlaces.contains(top.place.comparisonKey) else { return }
            let photos = moments.filter { planner.place(of: $0)?.comparisonKey == top.place.comparisonKey }.flatMap(planner.library.usablePhotos(in:))
            let plan = planner.engine.plan(IntelligenceRequest(pool: photos, target: .general(limit: 4), minimum: 1))
            toldPlaces.insert(top.place.comparisonKey)
            add(.placeHighlight, facts: .repeatedPlace(place: top.place.name, moments: top.moments, days: top.days, isYear: isYear),
                hero: hero(plan.selected), photos: plan.selected)
        }

        /// A day with clearly more memories than any other (not the first day, already told).
        mutating func busyDay(entries: [TemporalIndex.Entry], moments: [Moment]) {
            let byDay = Dictionary(grouping: entries) { DayKey(date: $0.date, calendar: calendar) }
            guard byDay.count >= 3 else { return }
            let counts = byDay.mapValues(\.count).sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            let top = counts[0], second = counts[1]
            let sortedCounts = counts.map(\.value).sorted()
            let median = sortedCounts[sortedCounts.count / 2]
            guard top.value >= 6, top.value > second.value, top.value >= 2 * median, !toldDays.contains(top.key) else { return }
            let ids = (byDay[top.key] ?? []).map(\.assetID).filter(planner.library.isUsable)
            let dayMoments = Set((byDay[top.key] ?? []).map(\.momentID))
            let places = Set(moments.filter { dayMoments.contains($0.id) }.compactMap { planner.place(of: $0)?.comparisonKey }).count
            let plan = planner.engine.plan(IntelligenceRequest(pool: ids, target: .general(limit: 4), minimum: 1))
            toldDays.insert(top.key)
            add(.dayHighlight, facts: .busyDay(dateLabel: planner.dayLabel(top.key), memories: top.value, places: places),
                hero: hero(plan.selected), photos: plan.selected)
        }

        /// Photos where analysis found two or more faces — only with enough distinct ones.
        mutating func people(usable: [AssetID]) {
            let candidates = MemoryCandidate.build(usable, library: planner.library).filter { ($0.faceCount ?? 0) >= 2 }
            guard candidates.count >= 4 else { return }
            let plan = planner.engine.plan(IntelligenceRequest(pool: candidates.map(\.assetID), target: .general(limit: 6), minimum: 1))
            guard plan.selected.count >= 4 else { return }
            add(.peopleGallery, facts: .people(count: plan.selected.count), hero: hero(plan.selected), photos: plan.selected)
        }

        mutating func favorites(usable: [AssetID]) {
            let favorites = usable.filter(planner.library.favoriteAssetIDs.contains)
            guard favorites.count >= 2 else { return }
            let plan = planner.engine.plan(IntelligenceRequest(pool: favorites, target: .general(limit: 6), minimum: 1))
            add(.favoriteHighlight, facts: .favorites(count: favorites.count), hero: hero(plan.selected), photos: plan.selected)
        }

        /// The period in frames: Memory Intelligence's diverse selection, when there are 4+.
        mutating func frames(_ selected: [AssetID]) {
            guard selected.count >= 4 else { return }
            add(.visualGrid, facts: .frames(periodName: name, count: selected.count), hero: nil, photos: selected)
        }

        mutating func places(moments: [Moment]) {
            guard insights.places.count >= 2 else { return }
            let rows = insights.places.prefix(6).map { place -> RecapChapter.Entry in
                let photos = moments.filter { planner.place(of: $0)?.comparisonKey == place.comparisonKey }.flatMap(planner.library.usablePhotos(in:))
                let lead = planner.engine.rankedLeads(photos, target: .general(limit: 1)).first
                return .init(title: place.name, detail: DeterministicEditorialTextProvider.count(photos.count, "memory", "memories"), photo: lead)
            }
            add(.places, facts: .places(count: insights.places.count, isYear: isYear), hero: nil, entries: rows)
        }

        /// The month's moments in order — at most six, chosen evenly, each with its own date.
        mutating func timeline(moments: [Moment]) {
            let dated = moments.filter { $0.startDate != nil }
            guard dated.count >= 3 else { return }
            let picked: [Moment] = dated.count <= 6 ? dated : (0..<6).map { dated[$0 * (dated.count - 1) / 5] }
            let rows = picked.map { moment -> RecapChapter.Entry in
                let day = DayKey(date: moment.startDate!, calendar: calendar)
                let title = moment.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
                return .init(title: planner.dayLabel(day), detail: title.isEmpty ? planner.place(of: moment)?.name : title,
                             photo: planner.library.lead(of: moment), momentID: moment.id)
            }
            add(.timeline, facts: .timeline(periodName: name, entries: rows.count), hero: nil, entries: rows)
        }

        mutating func closing(photos: [AssetID]) {
            add(.closing,
                facts: .closing(periodName: name, isYear: isYear, memories: insights.memoryCount, moments: insights.momentCount, places: insights.places.count),
                hero: hero(photos), photos: Array(photos.prefix(4)))
        }

        /// Keeps the chapter count within bounds by dropping the least essential first.
        mutating func trim(to limit: Int) {
            let order: [RecapChapter.Kind] = [.places, .favoriteHighlight, .peopleGallery, .dayHighlight, .timeline, .placeHighlight]
            for kind in order where chapters.count > limit {
                chapters.removeAll { $0.kind == kind }
            }
            chapters = chapters.enumerated().map { index, chapter in
                var chapter = chapter
                chapter.id = "\(chapter.kind.rawValue)-\(index)"
                return chapter
            }
        }
    }
}

extension RecapPeriod {
    var isYear: Bool {
        if case .year = self { return true }
        return false
    }
}
