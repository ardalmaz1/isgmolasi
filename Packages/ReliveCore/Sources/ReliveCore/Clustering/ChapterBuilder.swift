import Foundation

public struct ChapterConfiguration: Hashable, Sendable {
    /// Moments whose centres fall within this radius of a region's first moment share a region.
    public var regionRadius: Double
    /// A trip breaks when two consecutive moments are further apart in time than this.
    public var maximumGapBetweenMoments: TimeInterval
    /// Trips longer than this are split (a semester abroad is not one chapter).
    public var maximumSpan: TimeInterval
    public var minimumMoments: Int
    /// Trips must touch at least this many logical days; same-day outings stay separate moments.
    public var minimumLogicalDays: Int
    /// A region is "home" when it holds at least this share of located moments...
    public var homeMinimumShare: Double
    /// ...spread over at least this many distinct months.
    public var homeMinimumDistinctMonths: Int
    public var logicalDayStartHour: Int

    public init(
        regionRadius: Double = 40_000,
        maximumGapBetweenMoments: TimeInterval = 48 * 3600,
        maximumSpan: TimeInterval = 21 * 86_400,
        minimumMoments: Int = 2,
        minimumLogicalDays: Int = 2,
        homeMinimumShare: Double = 0.25,
        homeMinimumDistinctMonths: Int = 3,
        logicalDayStartHour: Int = 4
    ) {
        self.regionRadius = regionRadius
        self.maximumGapBetweenMoments = maximumGapBetweenMoments
        self.maximumSpan = maximumSpan
        self.minimumMoments = minimumMoments
        self.minimumLogicalDays = minimumLogicalDays
        self.homeMinimumShare = homeMinimumShare
        self.homeMinimumDistinctMonths = homeMinimumDistinctMonths
        self.logicalDayStartHour = logicalDayStartHour
    }

    public static let standard = ChapterConfiguration()
}

/// Minimal description of a moment candidate, enough to reason about trips.
public struct ClusterSummary: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var centroid: GeoCoordinate?

    public init(start: Date, end: Date, centroid: GeoCoordinate?) {
        self.start = start
        self.end = end
        self.centroid = centroid
    }
}

/// Groups consecutive moments into trips ("chapters").
///
/// ## Heuristic
///
/// 1. **Regions.** Located moments are grouped with simple leader clustering: a moment joins the
///    first region whose anchor lies within `regionRadius` (40 km — Kaş and Kekova share one);
///    otherwise it starts a new region.
/// 2. **Home.** A region is home-like when it holds ≥ 25 % of located moments across ≥ 3
///    distinct months. Several regions can qualify (long-distance couples have two homes).
///    Consecutive days at home are everyday life, not a trip.
/// 3. **Trips.** Walking chronologically, a trip is a run of moments in the same non-home
///    region, with ≤ 48 h between consecutive moments and ≤ 21 days overall. Unlocated moments
///    sandwiched inside a run join it; trailing ones don't. A run becomes a chapter when it has
///    ≥ 2 moments over ≥ 2 logical days.
///
/// Without location data no chapters are produced — reliability over cleverness.
public struct ChapterBuilder: Sendable {
    public var configuration: ChapterConfiguration
    public var calendar: Calendar

    public init(configuration: ChapterConfiguration = .standard, calendar: Calendar) {
        self.configuration = configuration
        self.calendar = calendar
    }

    /// Returns runs of indices into `clusters` (which must be chronological) that form chapters.
    public func chapterRuns(for clusters: [ClusterSummary]) -> [[Int]] {
        let regions = assignRegions(clusters)
        let homes = homeRegions(clusters: clusters, regions: regions)

        var runs: [[Int]] = []
        var current: [Int] = []
        var pendingUnlocated: [Int] = []
        var currentRegion: Int?

        func closeRun() {
            if qualifies(current, clusters: clusters) {
                runs.append(current)
            }
            current = []
            pendingUnlocated = []
            currentRegion = nil
        }

        for index in clusters.indices {
            let cluster = clusters[index]

            if let lastIndex = pendingUnlocated.last ?? current.last, let firstIndex = current.first {
                let gap = cluster.start.timeIntervalSince(clusters[lastIndex].end)
                let span = cluster.end.timeIntervalSince(clusters[firstIndex].start)
                if gap > configuration.maximumGapBetweenMoments || span > configuration.maximumSpan {
                    closeRun()
                }
            }

            guard let region = regions[index] else {
                if !current.isEmpty { pendingUnlocated.append(index) }
                continue
            }
            if homes.contains(region) {
                closeRun()
                continue
            }
            if region == currentRegion {
                current.append(contentsOf: pendingUnlocated)
                current.append(index)
                pendingUnlocated = []
            } else {
                closeRun()
                current = [index]
                currentRegion = region
            }
        }
        closeRun()
        return runs
    }

    /// Whether each cluster happened in a home-like region (everyday life rather than a trip).
    public func homeFlags(for clusters: [ClusterSummary]) -> [Bool] {
        let regions = assignRegions(clusters)
        let homes = homeRegions(clusters: clusters, regions: regions)
        return regions.map { region in region.map(homes.contains) ?? false }
    }

    /// Region index per cluster (nil when the cluster has no location).
    func assignRegions(_ clusters: [ClusterSummary]) -> [Int?] {
        var anchors: [GeoCoordinate] = []
        return clusters.map { cluster in
            guard let centroid = cluster.centroid else { return nil }
            if let existing = anchors.firstIndex(where: { $0.distance(to: centroid) <= configuration.regionRadius }) {
                return existing
            }
            anchors.append(centroid)
            return anchors.count - 1
        }
    }

    func homeRegions(clusters: [ClusterSummary], regions: [Int?]) -> Set<Int> {
        let located = regions.compactMap { $0 }
        guard !located.isEmpty else { return [] }

        var counts: [Int: Int] = [:]
        var months: [Int: Set<YearMonth>] = [:]
        for (index, region) in regions.enumerated() {
            guard let region else { continue }
            counts[region, default: 0] += 1
            months[region, default: []].insert(calendar.yearMonth(of: clusters[index].start))
        }

        let total = Double(located.count)
        return Set(counts.compactMap { region, count in
            let share = Double(count) / total
            let distinctMonths = months[region]?.count ?? 0
            let isHome = share >= configuration.homeMinimumShare
                && distinctMonths >= configuration.homeMinimumDistinctMonths
            return isHome ? region : nil
        })
    }

    private func qualifies(_ run: [Int], clusters: [ClusterSummary]) -> Bool {
        guard run.count >= configuration.minimumMoments else { return false }
        let dates = run.flatMap { [clusters[$0].start, clusters[$0].end] }
        let days = calendar.logicalDayCount(dates, startHour: configuration.logicalDayStartHour)
        return days >= configuration.minimumLogicalDays
    }
}
