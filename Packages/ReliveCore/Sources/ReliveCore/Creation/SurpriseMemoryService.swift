import Foundation

/// How long ago a surprise memory was, measured exactly from its capture date.
public enum SurpriseAnchor: Hashable, Sendable {
    case years(Int)
    case months(Int)
}

/// A memory brought back on Today because of when it happened: a whole number of years ago, or
/// six months ago, this week.
public struct SurpriseMemory: Hashable, Sendable {
    public var momentID: MomentID
    public var assetID: AssetID
    public var captureDate: Date
    public var anchor: SurpriseAnchor
    /// The same calendar day (rather than within a few days of it).
    public var isSameDay: Bool
    public var place: PlaceName?

    /// "A year ago today", "2 years ago this week", "6 months ago today".
    public var ageDescription: String {
        let base: String
        switch anchor {
        case .years(let years): base = years == 1 ? "A year ago" : "\(years) years ago"
        case .months(let months): base = months == 1 ? "A month ago" : "\(months) months ago"
        }
        return isSameDay ? "\(base) today" : "\(base) this week"
    }
}

public struct SurpriseMemoryConfiguration: Hashable, Sendable {
    /// A capture date this many days either side of the anniversary still counts ("this week").
    public var windowDays: Int
    /// After a day with a surprise, Today stays quiet for at least this many days.
    public var restDays: Int
    /// A moment shown on Today (by any card) isn't a surprise again for this long.
    public var momentCooldownDays: Int
    /// Month anniversaries offered besides whole years.
    public var monthAnchors: [Int]

    public init(windowDays: Int = 3, restDays: Int = 3, momentCooldownDays: Int = 14, monthAnchors: [Int] = [6]) {
        self.windowDays = windowDays
        self.restDays = restDays
        self.momentCooldownDays = momentCooldownDays
        self.monthAnchors = monthAnchors
    }

    public static let standard = SurpriseMemoryConfiguration()
}

/// Chooses an occasional Surprise Memory for Today.
///
/// Only memories whose capture date is a real anniversary qualify — so "A year ago this week"
/// is always true of the photo shown. It rests between surprises, skips moments shown recently,
/// hidden ones and ones the user asked not to see again, and is deterministic for a given day.
public struct SurpriseMemoryService: Sendable {
    public var configuration: SurpriseMemoryConfiguration
    public var library: CreationLibrary

    public init(library: CreationLibrary, configuration: SurpriseMemoryConfiguration = .standard) {
        self.library = library
        self.configuration = configuration
    }

    private var calendar: Calendar { library.calendar }

    /// The anniversary `date` has on `now`, if any.
    public func anchor(for date: Date, now: Date) -> (anchor: SurpriseAnchor, isSameDay: Bool)? {
        let today = calendar.startOfDay(for: now)
        guard calendar.startOfDay(for: date) < today else { return nil }

        func distance(adding component: Calendar.Component, _ value: Int) -> Int? {
            guard let shifted = calendar.date(byAdding: component, value: value, to: date) else { return nil }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: shifted), to: today).day
        }

        let years = calendar.dateComponents([.year], from: date, to: now).year ?? 0
        for candidate in [years, years + 1] where candidate >= 1 {
            if let days = distance(adding: .year, candidate), abs(days) <= configuration.windowDays {
                return (.years(candidate), days == 0)
            }
        }
        for months in configuration.monthAnchors {
            if let days = distance(adding: .month, months), abs(days) <= configuration.windowDays {
                return (.months(months), days == 0)
            }
        }
        return nil
    }

    /// - Parameters:
    ///   - lastSurpriseDay: the most recent day a surprise was shown (to rest between them).
    ///   - excluding: moments already on Today (e.g. Found for You).
    public func select(now: Date, lastSurpriseDay: Date?, excluding: Set<MomentID> = []) -> SurpriseMemory? {
        let today = calendar.startOfDay(for: now)
        if let last = lastSurpriseDay {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
            if days >= 0 && days <= configuration.restDays { return nil }
        }

        var best: (memory: SurpriseMemory, score: Double)?
        for moment in library.visibleMoments where moment.kind != .undated && !excluding.contains(moment.id) {
            let state = library.userStates[moment.id]
            if state?.isExcludedFromSurfacing == true { continue }
            if let shown = state?.lastSurfacedAt,
               let days = calendar.dateComponents([.day], from: shown, to: now).day,
               days < configuration.momentCooldownDays {
                continue
            }
            for id in library.usablePhotos(in: moment) {
                guard let asset = library.assets[id], let date = asset.creationDate,
                      let match = anchor(for: date, now: now) else { continue }
                var score = library.quality(id)
                if match.isSameDay { score += 1 }
                if case .years(let years) = match.anchor { score += 0.05 * Double(years) + 0.3 }
                if asset.isFavorite { score += 0.2 }
                let memory = SurpriseMemory(
                    momentID: moment.id,
                    assetID: id,
                    captureDate: date,
                    anchor: match.anchor,
                    isSameDay: match.isSameDay,
                    place: moment.place ?? library.story.chapter(for: moment)?.place
                )
                if let current = best {
                    if score < current.score - 1e-9 { continue }
                    if abs(score - current.score) <= 1e-9 && id >= current.memory.assetID { continue }
                }
                best = (memory, score)
            }
        }
        return best?.memory
    }

    /// Rebuilds a surprise chosen earlier today, if it is still true and still showable.
    public func restore(momentID: MomentID, assetID: AssetID, now: Date) -> SurpriseMemory? {
        guard let moment = library.story.moment(id: momentID), library.isVisible(moment),
              library.userStates[momentID]?.isExcludedFromSurfacing != true,
              moment.assetIDs.contains(assetID), library.isUsable(assetID),
              let date = library.assets[assetID]?.creationDate,
              let match = anchor(for: date, now: now) else { return nil }
        return SurpriseMemory(
            momentID: momentID,
            assetID: assetID,
            captureDate: date,
            anchor: match.anchor,
            isSameDay: match.isSameDay,
            place: moment.place ?? library.story.chapter(for: moment)?.place
        )
    }
}
