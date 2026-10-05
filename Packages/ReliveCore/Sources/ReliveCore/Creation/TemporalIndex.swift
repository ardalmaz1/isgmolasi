import Foundation

/// The one answer to "which month and year does this memory belong to?".
///
/// Every memory is placed by its **own** capture date (`MemoryAsset.creationDate` — the photo
/// library's capture date, read at import and refreshed by the metadata repair) in the library's
/// calendar. Never by the moment it belongs to, a neighbour's date, the date it was added, or
/// "now". So:
/// - a moment that runs past midnight into a new month (New Year's Eve) appears in both months,
///   each time with only the photos taken in that month;
/// - a memory without a capture date is counted as undated and placed in no month or year.
///
/// Monthly Recap, Our Year and the month and year creation sources all read from this index, so
/// one memory can never be "April 2025" in one feature and "September 2026" in another.
///
/// Memories are the members of visible moments that can still be shown, except duplicate copies
/// (the same image saved again) — the same rule as `StoryStatistics`.
public struct TemporalIndex: Sendable {
    public struct Entry: Hashable, Sendable {
        public var assetID: AssetID
        /// The memory's own capture date.
        public var date: Date
        public var month: MonthKey
        public var momentID: MomentID
    }

    public let calendar: Calendar
    /// Dated memories, chronological (capture date, then identifier).
    public let entries: [Entry]
    /// Memories without a capture date.
    public let undatedCount: Int
    private let moments: [Moment]

    public init(library: CreationLibrary) {
        calendar = library.calendar
        moments = library.visibleMoments
        var entries: [Entry] = []
        var undated = 0
        var seen = Set<AssetID>()
        for moment in moments {
            let duplicates = Set(moment.duplicateAssetIDs)
            for id in moment.assetIDs where !duplicates.contains(id) && library.isAvailable(id) && seen.insert(id).inserted {
                guard let date = library.assets[id]?.creationDate else {
                    undated += 1
                    continue
                }
                entries.append(Entry(assetID: id, date: date, month: MonthKey(date: date, calendar: library.calendar), momentID: moment.id))
            }
        }
        self.entries = entries.sorted { $0.date == $1.date ? $0.assetID < $1.assetID : $0.date < $1.date }
        undatedCount = undated
    }

    // MARK: - Calendar

    /// Months with at least one memory, newest first.
    public var months: [MonthKey] {
        Set(entries.map(\.month)).sorted(by: >)
    }

    /// Years with at least one memory, newest first.
    public var years: [Int] {
        Set(entries.map(\.month.year)).sorted(by: >)
    }

    /// Memories taken in `month`, chronological.
    public func entries(in month: MonthKey) -> [Entry] {
        entries.filter { $0.month == month }
    }

    /// Memories taken in `year`, chronological.
    public func entries(inYear year: Int) -> [Entry] {
        entries.filter { $0.month.year == year }
    }

    /// How many memories each month holds.
    public var countsByMonth: [MonthKey: Int] {
        entries.reduce(into: [:]) { $0[$1.month, default: 0] += 1 }
    }

    // MARK: - Moments

    /// The visible moments that hold any of `ids`, each narrowed to just those memories — same
    /// identity, title and place, but only these photos and only their dates. Chronological by
    /// the narrowed dates.
    public func moments(containing ids: Set<AssetID>) -> [Moment] {
        let dates = Dictionary(entries.filter { ids.contains($0.assetID) }.map { ($0.assetID, $0.date) }, uniquingKeysWith: { first, _ in first })
        let narrowed = moments.compactMap { moment -> Moment? in
            let members = moment.assetIDs.filter { ids.contains($0) && dates[$0] != nil }
            guard !members.isEmpty else { return nil }
            let kept = Set(members)
            var copy = moment
            copy.assetIDs = members
            copy.featuredAssetIDs = moment.featuredAssetIDs.filter(kept.contains)
            copy.similarAssetIDs = moment.similarAssetIDs.filter(kept.contains)
            copy.duplicateAssetIDs = []
            // Only collapsed shots of this moment fall in the period: show them rather than nothing.
            if copy.featuredAssetIDs.isEmpty {
                copy.featuredAssetIDs = members
                copy.similarAssetIDs = []
            }
            copy.heroAssetID = moment.heroAssetID.flatMap { kept.contains($0) ? $0 : nil }
            let memberDates = members.compactMap { dates[$0] }
            copy.startDate = memberDates.min()
            copy.endDate = memberDates.max()
            return copy
        }
        return narrowed.sorted { $0.sortDate == $1.sortDate ? $0.id.uuidString < $1.id.uuidString : $0.sortDate < $1.sortDate }
    }
}
