import Foundation

/// The couple's archive, ready to browse: every memory by month, every moment, every place.
///
/// Counted exactly like `StoryStatistics` (the numbers on Us), so "990 memories" opens 990
/// memories: hidden moments, unavailable photos and re-saved duplicate copies are left out;
/// near-identical shots are included (they are memories too). Identifiers only — no pixels.
/// Built once per story change; cost is linear in the number of memories.
public struct ArchiveIndex: Equatable, Sendable {
    /// Memories taken in one month (or the undated ones), in the order they were taken.
    public struct MonthGroup: Identifiable, Hashable, Sendable {
        /// "2025-08", or "undated".
        public var id: String
        public var month: MonthKey?
        public var assetIDs: [AssetID]
    }

    /// A place the couple's moments happened in. Named places are grouped by name; a location
    /// Relive couldn't name joins a named place within `unnamedPlaceRadius`, or stays a place of
    /// its own with no name (Relive never invents one).
    public struct Place: Identifiable, Hashable, Sendable {
        /// The name's comparison key, or "unnamed-<n>".
        public var id: String
        /// Nil when Relive couldn't name it.
        public var name: PlaceName?
        /// Its moments, in the order they happened.
        public var momentIDs: [MomentID]
        public var memoryCount: Int
        public var firstDate: Date?
        public var lastDate: Date?
        /// Distinct months with a moment here ("You returned": two or more).
        public var monthCount: Int
    }

    /// Newest month first; undated last.
    public var months: [MonthGroup]
    public var memoryCount: Int
    /// Visible moments, newest first (undated last).
    public var momentIDs: [MomentID]
    /// Most memories first (ties by name, then first date).
    public var places: [Place]

    public static let empty = ArchiveIndex(months: [], memoryCount: 0, momentIDs: [], places: [])

    public init(months: [MonthGroup], memoryCount: Int, momentIDs: [MomentID], places: [Place]) {
        self.months = months
        self.memoryCount = memoryCount
        self.momentIDs = momentIDs
        self.places = places
    }

    public func place(id: String) -> Place? {
        places.first { $0.id == id }
    }

    /// Memories newest month first, oldest-first inside a month — as the browser shows them.
    public var allAssetIDs: [AssetID] {
        months.flatMap(\.assetIDs)
    }

    public static func build(
        story: Story,
        assets: [AssetID: MemoryAsset],
        userStates: [MomentID: MomentUserState],
        isAvailable: (AssetID) -> Bool,
        calendar: Calendar,
        unnamedPlaceRadius: Double = 10_000
    ) -> ArchiveIndex {
        var seen = Set<AssetID>()
        var dated: [(date: Date, id: AssetID)] = []
        var undated: [AssetID] = []
        var moments: [Moment] = []

        for moment in story.moments where !(userStates[moment.id]?.isHidden ?? false) {
            let duplicates = Set(moment.duplicateAssetIDs)
            let shown = moment.assetIDs.filter { isAvailable($0) && !duplicates.contains($0) }
            guard !shown.isEmpty else { continue }
            moments.append(moment)
            for id in shown where seen.insert(id).inserted {
                if let date = assets[id]?.creationDate {
                    dated.append((date, id))
                } else {
                    undated.append(id)
                }
            }
        }

        // Memories by month.
        dated.sort { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        var months: [MonthGroup] = []
        var indexOfMonth: [MonthKey: Int] = [:]
        for entry in dated {
            let key = MonthKey(date: entry.date, calendar: calendar)
            if let index = indexOfMonth[key] {
                months[index].assetIDs.append(entry.id)
            } else {
                indexOfMonth[key] = months.count
                months.append(MonthGroup(id: Self.monthID(key), month: key, assetIDs: [entry.id]))
            }
        }
        months.reverse()
        if !undated.isEmpty {
            months.append(MonthGroup(id: "undated", month: nil, assetIDs: undated.sorted()))
        }

        // Moments, newest first.
        let datedMoments = moments.filter { $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantPast, $0.id.uuidString) > ($1.startDate ?? .distantPast, $1.id.uuidString) }
        let momentIDs = datedMoments.map(\.id) + moments.filter { $0.startDate == nil }.map(\.id)

        let places = Self.places(moments, isAvailable: isAvailable, calendar: calendar, radius: unnamedPlaceRadius)
        return ArchiveIndex(months: months, memoryCount: seen.count, momentIDs: momentIDs, places: places)
    }

    static func monthID(_ key: MonthKey) -> String {
        key.month < 10 ? "\(key.year)-0\(key.month)" : "\(key.year)-\(key.month)"
    }

    /// Same grouping as `StoryStatistics.placeCount`: named places by name; unnamed locations
    /// join the nearest named place within `radius`, otherwise group with each other by distance.
    private static func places(_ moments: [Moment], isAvailable: (AssetID) -> Bool, calendar: Calendar, radius: Double) -> [Place] {
        struct Building {
            var name: PlaceName?
            var anchors: [GeoCoordinate]
            var moments: [Moment]
        }
        var named: [String: Building] = [:]
        var namedOrder: [String] = []
        var unnamed: [Moment] = []
        for moment in moments {
            if let place = moment.place {
                let key = place.comparisonKey
                if named[key] == nil {
                    named[key] = Building(name: place, anchors: [], moments: [])
                    namedOrder.append(key)
                }
                named[key]?.moments.append(moment)
                if let centroid = moment.centroid { named[key]?.anchors.append(centroid) }
            } else if moment.centroid != nil {
                unnamed.append(moment)
            }
        }
        var extras: [Building] = []
        for moment in unnamed {
            guard let centroid = moment.centroid else { continue }
            // The nearest named place within reach.
            var nearest: (key: String, distance: Double)?
            for key in namedOrder {
                for anchor in named[key]?.anchors ?? [] {
                    let distance = anchor.distance(to: centroid)
                    if distance <= radius, distance < (nearest?.distance ?? .infinity) { nearest = (key, distance) }
                }
            }
            if let nearest {
                named[nearest.key]?.moments.append(moment)
                continue
            }
            if let index = extras.firstIndex(where: { $0.anchors.first.map { $0.distance(to: centroid) <= radius } ?? false }) {
                extras[index].moments.append(moment)
            } else {
                extras.append(Building(name: nil, anchors: [centroid], moments: [moment]))
            }
        }

        func make(_ id: String, _ building: Building) -> Place {
            let ordered = building.moments.sorted { ($0.startDate ?? .distantFuture, $0.id.uuidString) < ($1.startDate ?? .distantFuture, $1.id.uuidString) }
            let memories = ordered.reduce(0) { total, moment in
                let duplicates = Set(moment.duplicateAssetIDs)
                return total + moment.assetIDs.filter { isAvailable($0) && !duplicates.contains($0) }.count
            }
            let months = Set(ordered.compactMap { $0.startDate.map { MonthKey(date: $0, calendar: calendar) } })
            return Place(
                id: id,
                name: building.name,
                momentIDs: ordered.map(\.id),
                memoryCount: memories,
                firstDate: ordered.compactMap(\.startDate).min(),
                lastDate: ordered.compactMap { $0.endDate ?? $0.startDate }.max(),
                monthCount: months.count
            )
        }
        let all = namedOrder.compactMap { key in named[key].map { make(key, $0) } }
            + extras.enumerated().map { make("unnamed-\($0.offset)", $0.element) }
        return all.sorted { lhs, rhs in
            if lhs.memoryCount != rhs.memoryCount { return lhs.memoryCount > rhs.memoryCount }
            if (lhs.name == nil) != (rhs.name == nil) { return lhs.name != nil }
            if let a = lhs.name?.name, let b = rhs.name?.name, a != b { return a < b }
            return (lhs.firstDate ?? .distantFuture, lhs.id) < (rhs.firstDate ?? .distantFuture, rhs.id)
        }
    }
}
