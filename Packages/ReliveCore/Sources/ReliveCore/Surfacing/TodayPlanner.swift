import Foundation

/// A way back into the archive that Today can offer, beside the hero memory, Made for You and
/// "Continue your story". Each is a fact about the couple's own memories — never a feeling,
/// a ranking or a "best".
public enum TodayDiscovery: Hashable, Sendable {
    /// A moment from around this date in an earlier year ("A year ago · Bergama").
    case onThisDay(MomentID, yearsAgo: Int)
    /// A trip (two or more moments away) to look back on.
    case trip(UUID)
    /// A named place with moments in two or more different months.
    case returnedPlace(placeID: String)
    /// The most recent moment, when it is recent.
    case recentMoment(MomentID)

    /// The moments this item opens or shows, so Today never repeats one.
    public func momentIDs(story: Story, places: [ArchiveIndex.Place]) -> [MomentID] {
        switch self {
        case .onThisDay(let id, _), .recentMoment(let id): [id]
        case .trip(let id): story.chapter(id: id)?.momentIDs ?? []
        case .returnedPlace(let id): places.first { $0.id == id }?.momentIDs ?? []
        }
    }
}

/// Chooses at most a few archive discoveries for Today, only from real data, in a stable order
/// for the day (the same inputs on the same day give the same answer). Nothing is shown just to
/// fill space: a small or brand-new story may get none.
public struct TodayPlanner: Sendable {
    public var calendar: Calendar
    /// Today already has a hero, Made for You and "Continue": two more is plenty.
    public var maximumItems: Int
    /// "On this day" looks this many days either side of today's date.
    public var onThisDayWindow: Int
    /// A trip or moment younger than this isn't "worth revisiting" yet.
    public var minimumTripAge: TimeInterval
    /// "Recent" means started within this long.
    public var recentWindow: TimeInterval

    public init(
        calendar: Calendar,
        maximumItems: Int = 2,
        onThisDayWindow: Int = 3,
        minimumTripAge: TimeInterval = 30 * 86_400,
        recentWindow: TimeInterval = 45 * 86_400
    ) {
        self.calendar = calendar
        self.maximumItems = maximumItems
        self.onThisDayWindow = onThisDayWindow
        self.minimumTripAge = minimumTripAge
        self.recentWindow = recentWindow
    }

    /// - Parameters:
    ///   - visibleMoments: the moments the timeline shows (hidden ones never appear here).
    ///   - places: the archive's places.
    ///   - excluding: moments Today already shows (the hero, Made for You, "Continue").
    ///   - isRestingFromSurfacing: "Don't show this again" moments.
    public func discoveries(
        story: Story,
        visibleMoments: [Moment],
        places: [ArchiveIndex.Place],
        excluding: Set<MomentID>,
        isRestingFromSurfacing: (MomentID) -> Bool = { _ in false },
        now: Date
    ) -> [TodayDiscovery] {
        var used = excluding
        var items: [TodayDiscovery] = []
        let candidates = visibleMoments.filter { $0.kind != .undated && $0.startDate.map { $0 <= now } == true && !isRestingFromSurfacing($0.id) }
        let visibleIDs = Set(candidates.map(\.id))
        let seed = daySeed(now)

        func add(_ item: TodayDiscovery) {
            guard items.count < maximumItems else { return }
            let ids = item.momentIDs(story: story, places: places)
            guard !ids.isEmpty, used.isDisjoint(with: ids) else { return }
            items.append(item)
            used.formUnion(ids)
        }

        // 1. On this day, in an earlier year: the oldest first (a year ago, two years ago…).
        if let found = onThisDay(candidates, now: now, used: used) {
            add(.onThisDay(found.moment.id, yearsAgo: found.years))
        }

        // 2. A trip worth revisiting: two or more visible moments, over a while ago.
        let trips = story.chapters.filter { chapter in
            let members = chapter.momentIDs.filter(visibleIDs.contains)
            return members.count >= 2 && now.timeIntervalSince(chapter.endDate) >= minimumTripAge && used.isDisjoint(with: chapter.momentIDs)
        }
        .sorted { ($0.startDate, $0.id.uuidString) < ($1.startDate, $1.id.uuidString) }
        if !trips.isEmpty {
            add(.trip(trips[seed % trips.count].id))
        }

        // 3. A named place they returned to (moments there in two or more months).
        let returned = places.filter { place in
            place.name != nil && place.monthCount >= 2 && place.momentIDs.contains(where: visibleIDs.contains) && used.isDisjoint(with: place.momentIDs)
        }
        if !returned.isEmpty {
            add(.returnedPlace(placeID: returned[seed % returned.count].id))
        }

        // 4. The latest moment, while it is recent.
        if let latest = candidates.max(by: { ($0.startDate ?? .distantPast, $0.id.uuidString) < ($1.startDate ?? .distantPast, $1.id.uuidString) }),
           let start = latest.startDate, now.timeIntervalSince(start) <= recentWindow {
            add(.recentMoment(latest.id))
        }
        return items
    }

    /// A moment that began within `onThisDayWindow` days of today's date in an earlier year.
    func onThisDay(_ moments: [Moment], now: Date, used: Set<MomentID>) -> (moment: Moment, years: Int)? {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let thisYear = today.year else { return nil }
        var best: (moment: Moment, years: Int, distance: Int)?
        for moment in moments where !used.contains(moment.id) {
            guard let start = moment.startDate else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: start)
            guard let year = parts.year, year < thisYear else { continue }
            // The same date in this year (Feb 29 falls back to Feb 28).
            var same = DateComponents(year: thisYear, month: parts.month, day: parts.day)
            if calendar.date(from: same).map({ calendar.component(.month, from: $0) != parts.month }) == true {
                same.day = (parts.day ?? 1) - 1
            }
            guard let anniversary = calendar.date(from: same) else { continue }
            let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: anniversary), to: calendar.startOfDay(for: now)).day ?? .max)
            guard days <= onThisDayWindow else { continue }
            let years = thisYear - year
            if let current = best {
                // Closest to today first, then further back, then the earlier moment.
                if (days, -years, start) >= (current.distance, -current.years, current.moment.startDate ?? .distantFuture) { continue }
            }
            best = (moment, years, days)
        }
        return best.map { ($0.moment, $0.years) }
    }

    private func daySeed(_ now: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return abs((parts.year ?? 0) * 372 + (parts.month ?? 0) * 31 + (parts.day ?? 0))
    }
}
