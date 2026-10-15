import Foundation

/// What Relive noticed.
public enum SuggestionKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// A whole number of years ago, this day or week.
    case anniversary
    /// Months ago (e.g. six months ago this week).
    case throwback
    /// A recent month with enough in it.
    case monthRecap
    /// A year with memories across several months.
    case yearRecap
    /// A trip the story already knows.
    case trip
    /// One known place, across several years.
    case place
    /// A season — only when the hemisphere is known from the photos' own locations.
    case season
    /// A finished period ready to become a book.
    case memoryBook
}

/// One Made for You suggestion: real memories, a factual title, and what to make from them.
/// The quality that ranked it is internal and never shown.
public struct MadeForYouSuggestion: Hashable, Sendable, Codable, Identifiable {
    /// Stable across launches and story rebuilds ("month:2026-09", "trip:<first moment>").
    public var id: String
    public var kind: SuggestionKind
    /// "A year ago today", "Your month" — facts only.
    public var eyebrow: String
    public var title: String
    public var subtitle: String
    /// What opening it makes or shows.
    public var creation: CreationKind
    /// Where the creation's photos come from.
    public var source: CreationSource
    public var coverAssetID: AssetID?
    /// The photos the plan chose (the suggestion's preview), chronological.
    public var assetIDs: [AssetID]
    public var memoryCount: Int
    /// Every memory the suggestion stands for (for overlap suppression).
    var coverage: Set<AssetID>
    /// Internal rank. Never shown.
    var quality: Double
    /// The moment it comes from, for anniversaries (so Today doesn't repeat a surprise).
    public var momentID: MomentID?

    /// Strong enough to be the single Made for You card on Today.
    public var isStrongEnoughForToday: Bool {
        quality >= MadeForYouEngine.todayQuality && [.anniversary, .throwback, .monthRecap, .yearRecap, .trip].contains(kind)
    }
}

/// What the couple did with suggestions, kept on the device: shown, opened, dismissed, made.
/// No account, no server.
public struct SuggestionHistory: Hashable, Sendable, Codable {
    public struct Entry: Hashable, Sendable, Codable {
        public var firstShownAt: Date?
        public var lastShownDay: DayKey?
        /// Distinct days it was shown.
        public var shownDays: Int = 0
        public var openedAt: Date?
        public var dismissedAt: Date?
        public var createdAt: Date?
    }

    public var entries: [String: Entry] = [:]

    /// "Not now" keeps a suggestion away this long.
    public static let dismissDays = 90
    /// Once something was made from it, it stays away this long.
    public static let createdDays = 180
    /// Shown on this many days without being opened, it steps back so others get a turn.
    public static let rotationDays = 5

    public init() {}

    public mutating func recordShown(_ id: String, now: Date, calendar: Calendar) {
        var entry = entries[id] ?? Entry()
        let day = DayKey(date: now, calendar: calendar)
        if entry.lastShownDay != day {
            entry.shownDays += 1
            entry.lastShownDay = day
        }
        if entry.firstShownAt == nil { entry.firstShownAt = now }
        entries[id] = entry
    }

    public mutating func recordOpened(_ id: String, now: Date) {
        entries[id, default: Entry()].openedAt = now
    }

    public mutating func recordDismissed(_ id: String, now: Date) {
        entries[id, default: Entry()].dismissedAt = now
    }

    public mutating func recordCreated(_ id: String, now: Date) {
        entries[id, default: Entry()].createdAt = now
    }

    /// Hidden for now: dismissed recently, or already made.
    public func isSuppressed(_ id: String, now: Date) -> Bool {
        guard let entry = entries[id] else { return false }
        if let dismissed = entry.dismissedAt, now.timeIntervalSince(dismissed) < Double(Self.dismissDays) * 86_400 { return true }
        if let created = entry.createdAt, now.timeIntervalSince(created) < Double(Self.createdDays) * 86_400 { return true }
        return false
    }

    /// Steps back (never hidden) after being shown for a while without being opened.
    func rotationPenalty(_ id: String) -> Double {
        guard let entry = entries[id], entry.openedAt == nil else { return 0 }
        return entry.shownDays >= Self.rotationDays ? 1.0 : 0
    }
}

/// Finds a few suggestions worth making. Deterministic for a given story, day and history.
///
/// Every suggestion is built on a Memory Intelligence plan of real memories; anything without
/// enough real content — or without a true thing to call it — simply isn't suggested.
public struct MadeForYouEngine: Sendable {
    public var library: CreationLibrary
    public var now: Date
    public var history: SuggestionHistory
    /// When given, seasons use it; when nil, a season is offered only if the photos' own
    /// locations put every located photo of it in one hemisphere.
    public var hemisphere: PeriodDescriptor.Hemisphere?
    public var locale: Locale
    /// Suggestions below this internal quality never appear.
    public var minimumQuality = 1.0
    /// Today shows at most one suggestion, and only one at least this good.
    public static let todayQuality = 1.6
    /// Two suggestions sharing more than this share of the smaller one's memories are one too many.
    public var overlapLimit = 0.5

    public init(library: CreationLibrary, now: Date, history: SuggestionHistory = SuggestionHistory(), hemisphere: PeriodDescriptor.Hemisphere? = nil, locale: Locale = Locale(identifier: "en_US")) {
        self.library = library
        self.now = now
        self.history = history
        self.hemisphere = hemisphere
        self.locale = locale
    }

    private var calendar: Calendar { library.calendar }

    /// Up to `limit` suggestions, best first, with overlapping ones removed.
    public func suggestions(limit: Int = 4) -> [MadeForYouSuggestion] {
        guard !library.visibleMoments.isEmpty else { return [] }
        let index = TemporalIndex(library: library)
        var candidates: [MadeForYouSuggestion] = []
        candidates += anniversaries()
        candidates += months(index: index)
        candidates += years(index: index)
        candidates += trips()
        candidates += places()
        candidates += seasons(index: index)

        let ranked = candidates
            .filter { $0.quality >= minimumQuality && !history.isSuppressed($0.id, now: now) }
            .map { suggestion -> (MadeForYouSuggestion, Double) in
                (suggestion, Self.priority(suggestion.kind) + suggestion.quality - history.rotationPenalty(suggestion.id))
            }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 1e-9 { return lhs.1 > rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .map(\.0)

        var kept: [MadeForYouSuggestion] = []
        for suggestion in ranked where kept.count < limit {
            if kept.contains(where: { Self.overlap($0.coverage, suggestion.coverage) > overlapLimit }) { continue }
            kept.append(suggestion)
        }
        return kept
    }

    /// Anniversaries first, then a strong recent month, a trip, the year, a place, a season.
    static func priority(_ kind: SuggestionKind) -> Double {
        switch kind {
        case .anniversary: 3.0
        case .throwback: 2.4
        case .monthRecap: 2.2
        case .trip: 2.0
        case .yearRecap: 1.8
        case .place: 1.5
        case .season: 1.4
        case .memoryBook: 1.3
        }
    }

    /// Shared memories over the smaller suggestion's size.
    static func overlap(_ a: Set<AssetID>, _ b: Set<AssetID>) -> Double {
        let smaller = min(a.count, b.count)
        guard smaller > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(smaller)
    }

    // MARK: - Kinds

    /// The best real anniversary today (one), from capture dates only.
    func anniversaries() -> [MadeForYouSuggestion] {
        let surprises = SurpriseMemoryService(library: library)
        var best: MadeForYouSuggestion?
        for moment in library.visibleMoments where moment.kind != .undated {
            guard let start = moment.startDate, let match = surprises.anchor(for: start, now: now) else { continue }
            let usable = library.usablePhotos(in: moment)
            let favorite = library.favoriteMomentIDs.contains(moment.id) || usable.contains(where: library.favoriteAssetIDs.contains)
            // One meaningless photo isn't an anniversary worth a card; a favorite can be.
            guard usable.count >= 3 || (favorite && usable.count >= CreationLimits.collage.lowerBound) else { continue }
            let source = CreationSource.moment(moment.id)
            let creation: CreationKind = usable.count <= CreationLimits.collagePreselection ? .collage : .story
            let plan = plan(source, target: creation == .collage ? .collage : .story)
            guard plan.isReady else { continue }
            let kind: SuggestionKind
            let years: Int
            switch match.anchor {
            case .years(let value): kind = .anniversary; years = value
            case .months: kind = .throwback; years = 0
            }
            let memory = SurpriseMemory(momentID: moment.id, assetID: plan.lead ?? usable[0], captureDate: start, anchor: match.anchor, isSameDay: match.isSameDay, place: nil)
            let name = moment.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            let dateLabel = plan.period.label(locale: locale, calendar: calendar)
            var quality = quality(of: plan, coverage: usable)
            if match.isSameDay { quality += 0.3 }
            if favorite { quality += 0.2 }
            let suggestion = MadeForYouSuggestion(
                id: "anniversary:\(moment.id.uuidString):\(calendar.component(.year, from: now))-\(years)",
                kind: kind,
                eyebrow: memory.ageDescription,
                title: name.isEmpty ? (dateLabel ?? "A memory") : name,
                subtitle: [Self.count(usable.count, "memory", "memories"), dateLabel].compactMap { $0 }.joined(separator: " · "),
                creation: creation,
                source: source,
                coverAssetID: plan.lead,
                assetIDs: plan.selected,
                memoryCount: usable.count,
                coverage: Set(usable),
                quality: quality,
                momentID: moment.id
            )
            if best == nil || suggestion.quality > best!.quality + 1e-9 || (abs(suggestion.quality - best!.quality) <= 1e-9 && suggestion.id < best!.id) {
                best = suggestion
            }
        }
        return best.map { [$0] } ?? []
    }

    /// This month (once it has enough) and last month.
    func months(index: TemporalIndex) -> [MadeForYouSuggestion] {
        let current = MonthKey(date: now, calendar: calendar)
        let previous = current.month == 1 ? MonthKey(year: current.year - 1, month: 12) : MonthKey(year: current.year, month: current.month - 1)
        let builder = MonthlyRecapBuilder(library: library)
        return [current, previous].compactMap { month -> MadeForYouSuggestion? in
            let recap = builder.recap(for: month, index: index)
            let moments = recap.moments.count
            guard recap.isSufficient, recap.statistics.memoryCount >= 8, moments >= 2 else { return nil }
            let plan = plan(.month(month), target: .general(limit: 12))
            guard plan.isReady else { return nil }
            let coverage = recap.moments.flatMap(library.usablePhotos(in:))
            let monthName = MonthNames(locale: locale, calendar: calendar).full(month.month)
            return MadeForYouSuggestion(
                id: "month:\(month.year)-\(month.month)",
                kind: .monthRecap,
                eyebrow: "Your month",
                title: month.year == current.year ? "Your \(monthName)" : "\(monthName) \(month.year)",
                subtitle: "\(Self.count(recap.statistics.memoryCount, "memory", "memories")) · \(Self.count(moments, "moment", "moments"))",
                creation: .monthlyRecap,
                source: .month(month),
                coverAssetID: plan.lead,
                assetIDs: plan.selected,
                memoryCount: recap.statistics.memoryCount,
                coverage: Set(coverage),
                quality: quality(of: plan, coverage: coverage),
                momentID: nil
            )
        }
    }

    /// This year once it's a year; and, in its first months, last year — as Our Year, and as a
    /// book when it's rich enough.
    func years(index: TemporalIndex) -> [MadeForYouSuggestion] {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let builder = YearInReviewBuilder(library: library)
        var result: [MadeForYouSuggestion] = []
        for candidate in month <= 2 ? [year, year - 1] : [year] {
            let review = builder.review(for: candidate, index: index)
            guard review.isSufficient else { continue }
            let plan = plan(.year(candidate), target: .general(limit: 12))
            guard plan.isReady else { continue }
            let coverage = review.moments.flatMap(library.usablePhotos(in:))
            result.append(MadeForYouSuggestion(
                id: "year:\(candidate)",
                kind: .yearRecap,
                eyebrow: candidate == year ? "Your year so far" : "Your year",
                title: "Our \(candidate)",
                subtitle: "\(Self.count(review.statistics.memoryCount, "memory", "memories")) · \(Self.count(review.months.count, "month", "months"))",
                creation: .yearInReview,
                source: .year(candidate),
                coverAssetID: plan.lead,
                assetIDs: plan.selected,
                memoryCount: review.statistics.memoryCount,
                coverage: Set(coverage),
                quality: quality(of: plan, coverage: coverage),
                momentID: nil
            ))
        }
        // A finished year with plenty in it, as a book.
        let last = builder.review(for: year - 1, index: index)
        if last.isSufficient, last.statistics.memoryCount >= 20 {
            let plan = plan(.year(year - 1), target: .book)
            if plan.isReady {
                let coverage = last.moments.flatMap(library.usablePhotos(in:))
                result.append(MadeForYouSuggestion(
                    id: "book:year:\(year - 1)",
                    kind: .memoryBook,
                    eyebrow: "Ready to create",
                    title: "Our \(year - 1)",
                    subtitle: "Memory Book · \(Self.count(last.statistics.memoryCount, "memory", "memories"))",
                    creation: .book,
                    source: .year(year - 1),
                    coverAssetID: plan.lead,
                    assetIDs: plan.selected,
                    memoryCount: last.statistics.memoryCount,
                    coverage: Set(coverage),
                    quality: quality(of: plan, coverage: coverage) - 0.2,
                    momentID: nil
                ))
            }
        }
        return result
    }

    /// Trips the story knows, each made into what suits it best.
    func trips() -> [MadeForYouSuggestion] {
        library.visibleTrips.compactMap { trip -> MadeForYouSuggestion? in
            let moments = library.tripMoments(trip.id)
            let usable = moments.flatMap(library.usablePhotos(in:))
            guard usable.count >= 8, let first = moments.first else { return nil }
            let source = CreationSource.trip(trip.id)
            let general = plan(source, target: .general(limit: 40))
            // A large, varied trip is offered as a film; otherwise what suits it best.
            let preferred: [CreationKind] = [.movie, .book, .story, .collage]
            let available = Set(general.recommendations.filter(\.isAvailable).map(\.kind))
            let creation = preferred.first(where: available.contains) ?? .story
            let target: IntelligenceTarget = switch creation {
            case .movie: .general(limit: MovieSettings().length.sceneCap)
            case .book: .book
            case .story: .story
            default: .collage
            }
            let plan = plan(source, target: target)
            guard plan.isReady else { return nil }
            let name = trip.title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            let placeName = name.isEmpty ? (trip.place?.name ?? "") : name
            guard !placeName.isEmpty else { return nil }
            let period = general.period
            let when: String? = period.singleMonth.map { "\(MonthNames(locale: locale, calendar: calendar).full($0.month)) \($0.year)" }
                ?? period.label(locale: locale, calendar: calendar)
            let candidateDays = MemoryCandidate.build(usable, library: library).map(\.day)
            let days = Set(candidateDays.compactMap { $0 }).count
            let factualTitle = [placeName, when].compactMap { $0 }.joined(separator: " · ")
            // Presentation only: the engine chose the trip; editorial intelligence phrases it
            // ("Four days in Kaş."), from facts alone, through the shared validator.
            let allDated = !candidateDays.isEmpty && !candidateDays.contains(nil)
            let sortedDays = candidateDays.compactMap { $0 }.sorted()
            var context = EditorialContext(
                surface: .madeForYou,
                language: EditorialLanguage(locale: locale),
                firstDay: allDated ? sortedDays.first : nil,
                lastDay: allDated ? sortedDays.last : nil,
                months: allDated ? Self.months(of: sortedDays) : [],
                tripName: placeName,
                counts: EditorialContext.Counts(memories: usable.count, moments: moments.count),
                periodLabel: when,
                factualTitle: factualTitle
            )
            if let place = trip.place?.name, place != placeName { context.knownPhrases = [place] }
            let editorial = EditorialPipeline.shared.result(for: EditorialRequest(context: context, kind: .title))
            return MadeForYouSuggestion(
                id: "trip:\(first.id.uuidString)",
                kind: .trip,
                eyebrow: "A trip",
                title: editorial.text.isEmpty ? factualTitle : editorial.text,
                subtitle: [Self.count(usable.count, "memory", "memories"), when ?? Self.count(days, "day", "days")].joined(separator: " · "),
                creation: creation,
                source: source,
                coverAssetID: plan.lead,
                assetIDs: plan.selected,
                memoryCount: usable.count,
                coverage: Set(usable),
                quality: quality(of: general, coverage: usable),
                momentID: nil
            )
        }
    }

    /// One known place, visited in at least two different years.
    func places() -> [MadeForYouSuggestion] {
        var byPlace: [String: (place: PlaceName, moments: [Moment])] = [:]
        for moment in library.visibleMoments {
            guard let place = moment.place ?? library.story.chapter(for: moment)?.place else { continue }
            byPlace[place.comparisonKey, default: (place, [])].moments.append(moment)
        }
        return byPlace.sorted { $0.key < $1.key }.compactMap { key, entry -> MadeForYouSuggestion? in
            let usable = entry.moments.flatMap(library.usablePhotos(in:))
            let years = Set(usable.compactMap { library.assets[$0]?.creationDate.map { calendar.component(.year, from: $0) } })
            guard entry.moments.count >= 3, usable.count >= 8, years.count >= 2 else { return nil }
            let plan = MemoryIntelligenceEngine(library: library, locale: locale).quiet
                .plan(IntelligenceRequest(pool: usable, target: .story))
            guard plan.isReady, let first = years.min(), let last = years.max() else { return nil }
            return MadeForYouSuggestion(
                id: "place:\(key)",
                kind: .place,
                eyebrow: "Through the years",
                title: "\(entry.place.name) through the years",
                subtitle: "\(first) – \(last) · \(Self.count(usable.count, "memory", "memories"))",
                creation: .story,
                source: .photos(plan.selected),
                coverAssetID: plan.lead,
                assetIDs: plan.selected,
                memoryCount: usable.count,
                coverage: Set(usable),
                quality: quality(of: plan, coverage: usable),
                momentID: nil
            )
        }
    }

    /// The most recent finished seasons (this year and last), only with a known hemisphere.
    func seasons(index: TemporalIndex) -> [MadeForYouSuggestion] {
        let today = MonthKey(date: now, calendar: calendar)
        var result: [MadeForYouSuggestion] = []
        for year in [today.year, today.year - 1] {
            for season in PeriodDescriptor.Season.allCases {
                let entries = index.entries(inYear: year).filter { entry in
                    // Which months belong to the season depends on the hemisphere, decided below.
                    entry.month.year == year
                }
                guard !entries.isEmpty else { continue }
                let ids = entries.map(\.assetID).filter(library.isUsable)
                guard let hemisphere = hemisphere ?? Self.hemisphere(of: ids, library: library) else { continue }
                let months = season.months(in: hemisphere)
                // Only finished seasons.
                guard year < today.year || months.upperBound < today.month else { continue }
                let pool = entries.filter { months.contains($0.month.month) }.map(\.assetID).filter(library.isUsable)
                let momentCount = Set(entries.filter { months.contains($0.month.month) }.map(\.momentID)).count
                let monthCount = Set(entries.filter { months.contains($0.month.month) }.map(\.month)).count
                guard pool.count >= 12, monthCount >= 2, momentCount >= 3 else { continue }
                let plan = MemoryIntelligenceEngine(library: library, locale: locale).quiet
                    .plan(IntelligenceRequest(pool: pool, target: .book))
                guard plan.isReady, let label = plan.period.seasonLabel(hemisphere: hemisphere) else { continue }
                let places = Set(plan.selected.compactMap { library.creationAsset($0)?.place?.comparisonKey }).count
                result.append(MadeForYouSuggestion(
                    id: "season:\(year)-\(season)-\(hemisphere.rawValue)",
                    kind: .season,
                    eyebrow: "From your story",
                    title: label,
                    subtitle: [Self.count(pool.count, "memory", "memories"), places > 0 ? Self.count(places, "place", "places") : nil].compactMap { $0 }.joined(separator: " · "),
                    creation: .book,
                    source: .photos(plan.selected),
                    coverAssetID: plan.lead,
                    assetIDs: plan.selected,
                    memoryCount: pool.count,
                    coverage: Set(pool),
                    quality: quality(of: plan, coverage: pool),
                    momentID: nil
                ))
            }
        }
        return result
    }

    /// A hemisphere only when the photos' own locations agree: at least half are located and
    /// every located one is on the same side of the equator. Otherwise nil — never a guess.
    static func hemisphere(of ids: [AssetID], library: CreationLibrary) -> PeriodDescriptor.Hemisphere? {
        let latitudes = ids.compactMap { library.assets[$0]?.location.flatMap { $0.isValid ? $0.latitude : nil } }
        guard !ids.isEmpty, Double(latitudes.count) >= Double(ids.count) / 2 else { return nil }
        if latitudes.allSatisfy({ $0 > 0 }) { return .northern }
        if latitudes.allSatisfy({ $0 < 0 }) { return .southern }
        return nil
    }

    // MARK: - Quality

    /// How good a suggestion would be, from the plan and what it covers. Internal only.
    func quality(of plan: MemorySelectionPlan, coverage: [AssetID]) -> Double {
        let candidates = MemoryCandidate.build(coverage, library: library)
        guard !candidates.isEmpty else { return 0 }
        let usable = candidates.filter(\.isEligible)
        let size = min(1, log2(Double(max(1, usable.count))) / 5)              // 32 memories → 1
        let moments = Set(usable.compactMap(\.momentID)).count
        let days = Set(usable.compactMap(\.day)).count
        let diversity = min(0.5, 0.1 * Double(max(0, moments - 1)) + 0.05 * Double(max(0, days - 1)))
        let favorites = min(0.3, 0.1 * Double(usable.filter(\.isFavorite).count))
        let dated = usable.isEmpty ? 0 : Double(usable.filter { $0.captureDate != nil }.count) / Double(usable.count)
        let duplicateRatio = Double(plan.collapsedSimilar.count + plan.excludedDuplicates.count) / Double(max(1, plan.sourceCount))
        let averageQuality = usable.map(\.quality).reduce(0, +) / Double(max(1, usable.count))
        let periodKnown = plan.period.isComplete ? 0.2 : -0.5
        return 0.5 + size + diversity + favorites + periodKnown + 0.3 * min(1, averageQuality)
            - 0.5 * duplicateRatio - (1 - dated)
    }

    private func plan(_ source: CreationSource, target: IntelligenceTarget) -> MemorySelectionPlan {
        MemoryIntelligenceEngine(library: library, locale: locale).quiet.plan(for: source, target: target)
    }

    /// The months the days fall in, in order, each once.
    static func months(of days: [DayKey]) -> [MonthKey] {
        var seen = Set<MonthKey>()
        return days.sorted().map { MonthKey(year: $0.year, month: $0.month) }.filter { seen.insert($0).inserted }
    }

    static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }
}

extension MemoryIntelligenceEngine {
    /// The same engine without the DEBUG log line (for discovery, which plans many sources).
    var quiet: MemoryIntelligenceEngine {
        var engine = self
        engine.logsDiagnostics = false
        return engine
    }
}
