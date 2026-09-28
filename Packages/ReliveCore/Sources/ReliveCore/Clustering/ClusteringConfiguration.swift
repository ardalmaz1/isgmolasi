import Foundation

/// Tunables for `MomentClusterer`. See the clusterer's documentation for how they interact.
public struct ClusteringConfiguration: Hashable, Sendable {
    /// Gaps at or below this never split a moment (a dinner, a walk, a party).
    public var alwaysMergeGap: TimeInterval
    /// Floor of the adaptive split threshold.
    public var minimumSplitGap: TimeInterval
    /// Ceiling of the adaptive split threshold; longer gaps always split.
    public var maximumSplitGap: TimeInterval
    /// A gap splits when it is this many times longer than the local typical gap.
    public var densityFactor: Double
    /// Neighbouring gaps considered on each side when estimating the local typical gap.
    public var densityWindow: Int
    /// Hour at which a new "logical day" begins (late-night photos belong to the evening before).
    public var logicalDayStartHour: Int
    /// Gaps that cross into a new logical day and exceed this always split (people sleep).
    public var overnightSplitGap: TimeInterval
    /// Consecutive photos within this distance count as "still at the same place".
    public var samePlaceRadius: Double
    /// Consecutive photos further apart than this count as "somewhere else"...
    public var differentPlaceDistance: Double
    /// ...when at least this much time passed between them.
    public var differentPlaceMinimumGap: TimeInterval

    public init(
        alwaysMergeGap: TimeInterval = 30 * 60,
        minimumSplitGap: TimeInterval = 60 * 60,
        maximumSplitGap: TimeInterval = 8 * 3600,
        densityFactor: Double = 8,
        densityWindow: Int = 8,
        logicalDayStartHour: Int = 4,
        overnightSplitGap: TimeInterval = 3 * 3600,
        samePlaceRadius: Double = 1_500,
        differentPlaceDistance: Double = 25_000,
        differentPlaceMinimumGap: TimeInterval = 45 * 60
    ) {
        self.alwaysMergeGap = alwaysMergeGap
        self.minimumSplitGap = minimumSplitGap
        self.maximumSplitGap = maximumSplitGap
        self.densityFactor = densityFactor
        self.densityWindow = densityWindow
        self.logicalDayStartHour = logicalDayStartHour
        self.overnightSplitGap = overnightSplitGap
        self.samePlaceRadius = samePlaceRadius
        self.differentPlaceDistance = differentPlaceDistance
        self.differentPlaceMinimumGap = differentPlaceMinimumGap
    }

    public static let standard = ClusteringConfiguration()
}
