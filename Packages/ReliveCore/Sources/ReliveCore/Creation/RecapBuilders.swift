import Foundation

/// A look back at one calendar month. Every number is counted from the story with the same
/// rules as the rest of the app; nothing is added for months with little in them.
public struct MonthlyRecap: Sendable {
    public var month: MonthKey
    /// Visible moments that began this month, chronological.
    public var moments: [Moment]
    /// Trips with at least one of those moments.
    public var chapters: [Chapter]
    public var statistics: StoryStatistics
    public var dateSpan: DateSpan?
    /// Distinct named places, in the order they were visited.
    public var places: [PlaceName]
    /// Enough to make something from (see `MonthlyRecapBuilder.minimumMemories`).
    public var isSufficient: Bool
    /// Photos interleaved across moments, best of each first.
    var interleavedPhotos: [AssetID]
    var chronologicalRank: [AssetID: Int]

    /// The best photos of the month, spread across its moments, in the order they were taken.
    public func highlights(limit: Int) -> [AssetID] {
        Array(interleavedPhotos.prefix(limit)).sorted { (chronologicalRank[$0] ?? 0) < (chronologicalRank[$1] ?? 0) }
    }
}

public struct MonthlyRecapBuilder: Sendable {
    public var library: CreationLibrary
    /// Fewer memories than this and the month gets a gentle "not enough yet" instead of a recap.
    public var minimumMemories: Int

    public init(library: CreationLibrary, minimumMemories: Int = 4) {
        self.library = library
        self.minimumMemories = minimumMemories
    }

    /// Months with at least one visible dated moment, newest first.
    public func availableMonths() -> [MonthKey] {
        let months = Set(library.visibleMoments.compactMap { moment in
            moment.kind == .undated ? nil : moment.startDate.map { MonthKey(date: $0, calendar: library.calendar) }
        })
        return months.sorted(by: >)
    }

    public func recap(for month: MonthKey) -> MonthlyRecap {
        let moments = library.visibleMoments.filter { moment in
            guard moment.kind != .undated, let start = moment.startDate else { return false }
            return MonthKey(date: start, calendar: library.calendar) == month
        }
        let summary = RecapSummary(moments: moments, library: library)
        let usableCount = moments.reduce(0) { $0 + library.usablePhotos(in: $1).count }
        return MonthlyRecap(
            month: month,
            moments: moments,
            chapters: summary.chapters,
            statistics: summary.statistics,
            dateSpan: summary.dateSpan,
            places: summary.places,
            isSufficient: summary.statistics.memoryCount >= minimumMemories && usableCount >= 3,
            interleavedPhotos: summary.interleave(moments.map { summary.ranked($0) }),
            chronologicalRank: summary.chronologicalRank
        )
    }
}

/// One month inside a year.
public struct YearMonthSection: Sendable, Identifiable {
    public var month: MonthKey
    public var moments: [Moment]
    /// Trips that began this month.
    public var chapters: [Chapter]
    public var memoryCount: Int
    /// Up to four of the month's best photos, in the order they were taken.
    public var highlights: [AssetID]

    public var id: MonthKey { month }
}

/// Whether a year has enough in it to be shown as a year — not just a month called a year.
public enum YearEligibility: Hashable, Sendable {
    case eligible
    /// Nothing from this year.
    case empty
    /// Everything is from one month ("Your 2026 story is just getting started").
    case singleMonth(MonthKey)
    /// Several months, but too few memories or moments to look back on yet.
    case tooFew(memories: Int)
}

/// A year together, month by month, built only from what the story contains.
public struct YearInReview: Sendable {
    public var year: Int
    public var moments: [Moment]
    public var chapters: [Chapter]
    public var statistics: StoryStatistics
    public var dateSpan: DateSpan?
    public var places: [PlaceName]
    /// Months that have memories, chronological. Months without any are not listed.
    public var months: [YearMonthSection]
    public var eligibility: YearEligibility
    var interleavedPhotos: [AssetID]
    var chronologicalRank: [AssetID: Int]

    public var firstMoment: Moment? { moments.first }
    public var lastMoment: Moment? { moments.last }

    /// Enough to present as "Our <year>": memories from at least two months, and enough of them.
    public var isSufficient: Bool { eligibility == .eligible }

    /// The best photos of the year, spread across its months, in the order they were taken.
    public func highlights(limit: Int) -> [AssetID] {
        Array(interleavedPhotos.prefix(limit)).sorted { (chronologicalRank[$0] ?? 0) < (chronologicalRank[$1] ?? 0) }
    }
}

public struct YearInReviewBuilder: Sendable {
    public var library: CreationLibrary
    public var minimumMemories: Int
    public var minimumMoments: Int
    /// A year needs memories from at least this many different months.
    public var minimumMonths: Int

    public init(library: CreationLibrary, minimumMemories: Int = 8, minimumMoments: Int = 2, minimumMonths: Int = 2) {
        self.library = library
        self.minimumMemories = minimumMemories
        self.minimumMoments = minimumMoments
        self.minimumMonths = minimumMonths
    }

    /// Years with at least one visible dated moment, newest first.
    public func availableYears() -> [Int] {
        let years = Set(library.visibleMoments.compactMap { moment in
            moment.kind == .undated ? nil : moment.startDate.map { library.calendar.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    public func review(for year: Int) -> YearInReview {
        let calendar = library.calendar
        let moments = library.visibleMoments.filter { moment in
            guard moment.kind != .undated, let start = moment.startDate else { return false }
            return calendar.component(.year, from: start) == year
        }
        let summary = RecapSummary(moments: moments, library: library)

        var sections: [YearMonthSection] = []
        var monthGroups: [[AssetID]] = []
        for moment in moments {
            guard let start = moment.startDate else { continue }
            let key = MonthKey(date: start, calendar: calendar)
            if sections.last?.month != key {
                sections.append(YearMonthSection(month: key, moments: [], chapters: [], memoryCount: 0, highlights: []))
            }
            sections[sections.count - 1].moments.append(moment)
        }
        for index in sections.indices {
            let monthMoments = sections[index].moments
            let monthSummary = RecapSummary(moments: monthMoments, library: library)
            let interleaved = monthSummary.interleave(monthMoments.map { monthSummary.ranked($0) })
            monthGroups.append(interleaved)
            sections[index].memoryCount = monthSummary.statistics.memoryCount
            sections[index].highlights = Array(interleaved.prefix(4))
                .sorted { (summary.chronologicalRank[$0] ?? 0) < (summary.chronologicalRank[$1] ?? 0) }
            // A trip belongs to the month it began in.
            sections[index].chapters = summary.chapters.filter { chapter in
                MonthKey(date: chapter.startDate, calendar: calendar) == sections[index].month
            }
        }

        return YearInReview(
            year: year,
            moments: moments,
            chapters: summary.chapters,
            statistics: summary.statistics,
            dateSpan: summary.dateSpan,
            places: summary.places,
            months: sections,
            eligibility: eligibility(months: sections, memories: summary.statistics.memoryCount, moments: moments.count),
            interleavedPhotos: summary.interleave(monthGroups),
            chronologicalRank: summary.chronologicalRank
        )
    }
}

extension YearInReviewBuilder {
    /// Deterministic: at least `minimumMonths` different months, `minimumMemories` memories and
    /// `minimumMoments` moments.
    func eligibility(months: [YearMonthSection], memories: Int, moments: Int) -> YearEligibility {
        guard let first = months.first, memories > 0 else { return .empty }
        if months.count < minimumMonths { return .singleMonth(first.month) }
        if memories < minimumMemories || moments < minimumMoments { return .tooFew(memories: memories) }
        return .eligible
    }
}

/// Shared counting for recaps.
struct RecapSummary {
    let moments: [Moment]
    let library: CreationLibrary
    let statistics: StoryStatistics
    let chapters: [Chapter]
    let places: [PlaceName]
    let dateSpan: DateSpan?
    let chronologicalRank: [AssetID: Int]

    init(moments: [Moment], library: CreationLibrary) {
        self.moments = moments
        self.library = library

        var chapters: [Chapter] = []
        for moment in moments {
            if let chapter = library.story.chapter(for: moment), !chapters.contains(where: { $0.id == chapter.id }) {
                chapters.append(chapter)
            }
        }
        self.chapters = chapters
        self.statistics = StoryStatistics.compute(
            story: Story(generatedAt: library.story.generatedAt, moments: moments, chapters: chapters),
            assets: library.assets,
            userStates: library.userStates,
            isAvailable: library.isAvailable
        )

        var places: [PlaceName] = []
        for moment in moments {
            if let place = moment.place ?? library.story.chapter(for: moment)?.place,
               !places.contains(where: { $0.comparisonKey == place.comparisonKey }) {
                places.append(place)
            }
        }
        self.places = places
        self.dateSpan = DateSpan(dates: moments.compactMap(\.startDate) + moments.compactMap(\.endDate))

        let photos = moments.flatMap { library.usablePhotos(in: $0) }.sorted(by: library.chronologicalOrder)
        self.chronologicalRank = Dictionary(photos.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    /// A moment's usable photos, its lead first, then best to worst.
    func ranked(_ moment: Moment) -> [AssetID] {
        let usable = library.usablePhotos(in: moment)
        let lead = library.lead(of: moment)
        let rest = usable.filter { $0 != lead }.sorted { lhs, rhs in
            let left = library.quality(lhs), right = library.quality(rhs)
            if abs(left - right) > 1e-9 { return left > right }
            return library.chronologicalOrder(lhs, rhs)
        }
        return (lead.map { [$0] } ?? []) + rest
    }

    /// Takes one from each group in turn, so a handful of highlights covers every group.
    func interleave(_ groups: [[AssetID]]) -> [AssetID] {
        var result: [AssetID] = []
        var seen = Set<AssetID>()
        let longest = groups.map(\.count).max() ?? 0
        for round in 0..<longest {
            for group in groups where round < group.count {
                if seen.insert(group[round]).inserted {
                    result.append(group[round])
                }
            }
        }
        return result
    }
}
