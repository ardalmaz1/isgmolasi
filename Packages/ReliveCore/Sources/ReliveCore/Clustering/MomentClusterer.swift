import Foundation

/// Stages 4–5 — splits a chronological list of assets into candidate moments using time
/// gaps, shooting density and location.
///
/// ## Heuristic
///
/// Walk the assets in capture order and decide, for each gap between two consecutive assets,
/// whether it starts a new moment. Rules are evaluated in order; the first that applies wins:
///
/// 1. **Short gap → same moment.** Gaps ≤ `alwaysMergeGap` (30 min) never split.
/// 2. **Slept in between → new moment.** The gap crosses into a new *logical day* (days start
///    at 04:00, so a 00:40 photo belongs to the evening before) and is ≥ `overnightSplitGap`
///    (3 h).
/// 3. **Very long gap → new moment.** Gaps ≥ `maximumSplitGap` (8 h) always split.
/// 4. **Somewhere else → new moment.** Both sides have a location, they are ≥ 25 km apart and
///    ≥ 45 min passed.
/// 5. **Still at the same place → same moment.** Both sides have a location within 1.5 km
///    (a long afternoon at the same beach stays one moment).
/// 6. **Adaptive density rule.** Otherwise compare the gap with the *local typical gap* — the
///    median of up to `densityWindow` neighbouring gaps on each side. The gap splits when it
///    exceeds `densityFactor ×` that median, clamped to [`minimumSplitGap`, `maximumSplitGap`]
///    (1 h … 8 h). People who shoot in dense bursts get split at an hour's pause; people who
///    take one photo every couple of hours keep their whole day together.
///
/// The adaptive rule follows the idea behind PhotoTOC (Platt et al., 2003): event boundaries
/// are gaps that are unusually long *relative to the surrounding gaps*, not relative to a fixed
/// constant. The explicit rules around it keep the result believable in the common cases.
///
/// "Same location" uses the most recent located asset of the current moment, so a few
/// photos without GPS in the middle of a located sequence don't break the comparison.
public struct MomentClusterer: Sendable {
    public var configuration: ClusteringConfiguration
    public var calendar: Calendar

    public init(configuration: ClusteringConfiguration = .standard, calendar: Calendar) {
        self.configuration = configuration
        self.calendar = calendar
    }

    /// Why a boundary was (or wasn't) placed. Exposed for tests and tuning.
    public enum GapDecision: Equatable, Sendable {
        case mergeShortGap
        case splitOvernight
        case splitLongGap
        case splitDifferentPlace
        case mergeSamePlace
        case mergeWithinDensity(threshold: TimeInterval)
        case splitBeyondDensity(threshold: TimeInterval)

        public var splits: Bool {
            switch self {
            case .splitOvernight, .splitLongGap, .splitDifferentPlace, .splitBeyondDensity: true
            case .mergeShortGap, .mergeSamePlace, .mergeWithinDensity: false
            }
        }
    }

    /// Groups assets into clusters. Assets must have a creation date; undated input is ignored.
    public func cluster(_ assets: [MemoryAsset]) -> [[MemoryAsset]] {
        let sorted = assets.filter { $0.creationDate != nil }.sorted(by: MetadataProcessor.chronological)
        guard let first = sorted.first else { return [] }

        let gaps = MomentClusterer.gaps(of: sorted)
        var clusters: [[MemoryAsset]] = []
        var current: [MemoryAsset] = [first]
        var lastLocation = first.location

        for index in 1..<sorted.count {
            let asset = sorted[index]
            let decision = decide(
                previous: sorted[index - 1],
                next: asset,
                lastKnownLocation: lastLocation,
                gapIndex: index - 1,
                gaps: gaps
            )
            if decision.splits {
                clusters.append(current)
                current = [asset]
                lastLocation = asset.location
            } else {
                current.append(asset)
                if let location = asset.location { lastLocation = location }
            }
        }
        clusters.append(current)
        return clusters
    }

    /// Decision for the gap between two consecutive (chronological) assets.
    public func decide(
        previous: MemoryAsset,
        next: MemoryAsset,
        lastKnownLocation: GeoCoordinate?,
        gapIndex: Int,
        gaps: [TimeInterval]
    ) -> GapDecision {
        guard let start = previous.creationDate, let end = next.creationDate else { return .splitLongGap }
        let gap = end.timeIntervalSince(start)
        let config = configuration

        if gap <= config.alwaysMergeGap {
            return .mergeShortGap
        }
        if gap >= config.overnightSplitGap,
           !calendar.isSameLogicalDay(start, end, startHour: config.logicalDayStartHour) {
            return .splitOvernight
        }
        if gap >= config.maximumSplitGap {
            return .splitLongGap
        }
        if let from = lastKnownLocation ?? previous.location, let to = next.location {
            let distance = from.distance(to: to)
            if distance >= config.differentPlaceDistance, gap >= config.differentPlaceMinimumGap {
                return .splitDifferentPlace
            }
            if distance <= config.samePlaceRadius {
                return .mergeSamePlace
            }
        }

        let threshold = adaptiveThreshold(gapIndex: gapIndex, gaps: gaps)
        return gap > threshold ? .splitBeyondDensity(threshold: threshold) : .mergeWithinDensity(threshold: threshold)
    }

    /// `densityFactor ×` the median of neighbouring gaps, clamped to the configured bounds.
    public func adaptiveThreshold(gapIndex: Int, gaps: [TimeInterval]) -> TimeInterval {
        let window = max(1, configuration.densityWindow)
        let lower = max(0, gapIndex - window)
        let upper = min(gaps.count - 1, gapIndex + window)
        var neighbours: [Double] = []
        if lower <= upper {
            for index in lower...upper where index != gapIndex {
                neighbours.append(gaps[index])
            }
        }
        let typical = Statistics.median(neighbours) ?? configuration.maximumSplitGap
        let raw = typical * configuration.densityFactor
        return min(configuration.maximumSplitGap, max(configuration.minimumSplitGap, raw))
    }

    static func gaps(of sorted: [MemoryAsset]) -> [TimeInterval] {
        guard sorted.count > 1 else { return [] }
        return (1..<sorted.count).map { index in
            guard let lhs = sorted[index - 1].creationDate, let rhs = sorted[index].creationDate else { return 0 }
            return rhs.timeIntervalSince(lhs)
        }
    }
}
