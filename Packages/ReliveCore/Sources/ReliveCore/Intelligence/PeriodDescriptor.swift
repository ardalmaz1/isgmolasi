import Foundation

/// The period a set of memories covers, from their own capture dates in the library calendar
/// (the same calendar `TemporalIndex` and `CreationMetadata` use, so the month and year of a
/// photo are the same everywhere).
///
/// Never forces a single month onto mixed-period content, and never borrows a date: photos
/// without one are counted, not dated.
public struct PeriodDescriptor: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        /// Every dated memory is from this day.
        case day(DayKey)
        /// Several days within one month.
        case days(first: DayKey, last: DayKey)
        case month(MonthKey)
        /// Several months of one year.
        case months(first: MonthKey, last: MonthKey)
        /// Several years.
        case years(first: Int, last: Int)
        /// No memory has a date.
        case unknown
    }

    /// Days of one month at most this far apart are described as days ("June 8–10").
    public static let dayRangeLimit = 6

    public var kind: Kind
    /// Memories with and without a capture date.
    public var datedCount: Int
    public var undatedCount: Int
    /// The place every memory shares, when they all have the same known place.
    public var commonPlace: PlaceName?

    /// True only when every memory has a date (the period describes all of them).
    public var isComplete: Bool { undatedCount == 0 && datedCount > 0 }

    public init(kind: Kind, datedCount: Int, undatedCount: Int, commonPlace: PlaceName?) {
        self.kind = kind
        self.datedCount = datedCount
        self.undatedCount = undatedCount
        self.commonPlace = commonPlace
    }

    /// The period of `candidates`.
    public init(candidates: [MemoryCandidate]) {
        let days = candidates.compactMap(\.day)
        let undated = candidates.count - days.count
        var place: PlaceName?
        if let first = candidates.first?.place,
           candidates.allSatisfy({ $0.place?.comparisonKey == first.comparisonKey }) {
            place = first
        }
        guard let first = days.min(), let last = days.max() else {
            self.init(kind: .unknown, datedCount: 0, undatedCount: undated, commonPlace: place)
            return
        }
        let kind: Kind
        if first == last {
            kind = .day(first)
        } else if first.monthKey == last.monthKey {
            // A few days (a weekend, a short trip) read as those days; more of a month as the month.
            kind = last.day - first.day <= Self.dayRangeLimit ? .days(first: first, last: last) : .month(first.monthKey)
        } else if first.year == last.year {
            kind = .months(first: first.monthKey, last: last.monthKey)
        } else {
            kind = .years(first: first.year, last: last.year)
        }
        self.init(kind: kind, datedCount: days.count, undatedCount: undated, commonPlace: place)
    }

    /// The single month, when every dated memory is from one month.
    public var singleMonth: MonthKey? {
        switch kind {
        case .day(let day): day.monthKey
        case .days(let first, _): first.monthKey
        case .month(let month): month
        default: nil
        }
    }

    /// The single year, when every dated memory is from one year.
    public var singleYear: Int? {
        switch kind {
        case .day(let day): day.year
        case .days(let first, _): first.year
        case .month(let month): month.year
        case .months(let first, _): first.year
        case .years, .unknown: nil
        }
    }

    /// Distinct calendar years the period touches (for "Our 2026" vs "2025 – 2026").
    public var spansYears: Bool {
        if case .years = kind { return true }
        return false
    }

    // MARK: - Labels

    /// "June 8, 2026", "June 8–10, 2026", "August 2026", "August – October 2026", "2025 – 2026".
    /// Nil when no memory has a date.
    public func label(locale: Locale = .reliveDisplay, calendar: Calendar) -> String? {
        let names = MonthNames(locale: locale, calendar: calendar)
        switch kind {
        case .unknown:
            return nil
        case .day(let day):
            return "\(names.full(day.month)) \(day.day), \(day.year)"
        case .days(let first, let last):
            return "\(names.full(first.month)) \(first.day)–\(last.day), \(first.year)"
        case .month(let month):
            return "\(names.full(month.month)) \(month.year)"
        case .months(let first, let last):
            return "\(names.full(first.month)) – \(names.full(last.month)) \(first.year)"
        case .years(let first, let last):
            return "\(first) – \(last)"
        }
    }

    /// "Summer 2026", only when every dated memory is from one year's June–August (or
    /// December–February, or the other quarters) *and* the caller says which hemisphere the
    /// couple lives in — seasons are not the same everywhere, so Relive never assumes one.
    public func seasonLabel(hemisphere: Hemisphere?) -> String? {
        guard let hemisphere, isComplete else { return nil }
        let range: (MonthKey, MonthKey)
        switch kind {
        case .day(let day): range = (day.monthKey, day.monthKey)
        case .days(let first, let last): range = (first.monthKey, last.monthKey)
        case .month(let month): range = (month, month)
        case .months(let first, let last): range = (first, last)
        case .years, .unknown: return nil
        }
        // Spanning more than one month is required for a season to say more than the month.
        guard range.0 != range.1 else { return nil }
        for season in Season.allCases {
            let months = season.months(in: hemisphere)
            if months.contains(range.0.month), months.contains(range.1.month), range.0.month <= range.1.month {
                return "\(season.name) \(range.0.year)"
            }
        }
        return nil
    }

    public enum Hemisphere: String, Hashable, Sendable, Codable {
        case northern
        case southern
    }

    enum Season: CaseIterable {
        case spring, summer, autumn, winter

        var name: String {
            switch self {
            case .spring: CoreWords().pick("Spring", "İlkbahar")
            case .summer: CoreWords().pick("Summer", "Yaz")
            case .autumn: CoreWords().pick("Autumn", "Sonbahar")
            case .winter: CoreWords().pick("Winter", "Kış")
            }
        }

        /// Months within one calendar year (winter's January–February only, so a range never
        /// wraps across a new year).
        func months(in hemisphere: Hemisphere) -> ClosedRange<Int> {
            switch (self, hemisphere) {
            case (.spring, .northern), (.autumn, .southern): 3...5
            case (.summer, .northern), (.winter, .southern): 6...8
            case (.autumn, .northern), (.spring, .southern): 9...11
            case (.winter, .northern), (.summer, .southern): 1...2
            }
        }
    }
}

/// Month names from the calendar's own symbols, in `locale`.
struct MonthNames {
    let symbols: [String]

    init(locale: Locale, calendar: Calendar) {
        var calendar = calendar
        calendar.locale = locale
        symbols = calendar.standaloneMonthSymbols
    }

    func full(_ month: Int) -> String {
        symbols.indices.contains(month - 1) ? symbols[month - 1] : String(month)
    }
}
