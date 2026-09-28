import Foundation

public struct FoundForYouConfiguration: Hashable, Sendable {
    /// Memories younger than this are not "rediscoveries" (used only while older ones exist).
    public var minimumAge: TimeInterval
    /// A moment shown recently rests for this long.
    public var cooldown: TimeInterval
    /// Age at which the age score saturates.
    public var fullAgeScoreAfter: TimeInterval
    public var ageWeight: Double
    public var qualityWeight: Double
    public var anniversaryBonus: Double
    public var favoriteBonus: Double
    /// Subtracted per previous showing, so rotation favours memories not seen yet.
    public var repeatPenalty: Double
    /// Small deterministic day-to-day variation so equal candidates take turns.
    public var dailyVariation: Double

    public init(
        minimumAge: TimeInterval = 60 * 86_400,
        cooldown: TimeInterval = 21 * 86_400,
        fullAgeScoreAfter: TimeInterval = 2 * 365 * 86_400,
        ageWeight: Double = 0.35,
        qualityWeight: Double = 0.45,
        anniversaryBonus: Double = 0.35,
        favoriteBonus: Double = 0.2,
        repeatPenalty: Double = 0.1,
        dailyVariation: Double = 0.08
    ) {
        self.minimumAge = minimumAge
        self.cooldown = cooldown
        self.fullAgeScoreAfter = fullAgeScoreAfter
        self.ageWeight = ageWeight
        self.qualityWeight = qualityWeight
        self.anniversaryBonus = anniversaryBonus
        self.favoriteBonus = favoriteBonus
        self.repeatPenalty = repeatPenalty
        self.dailyVariation = dailyVariation
    }

    public static let standard = FoundForYouConfiguration()
}

/// A memory chosen for the Today screen.
public struct FoundMemory: Hashable, Sendable {
    public var momentID: MomentID
    public var assetID: AssetID
    public var captureDate: Date?
    /// "2 years ago", "A year ago this week"
    public var ageDescription: String
    public var place: PlaceName?
}

/// Picks one older, good-looking memory that hasn't been shown recently.
///
/// Deterministic for a given day: the same inputs on the same day give the same answer, so the
/// Today screen doesn't reshuffle every time it appears. Hidden moments and moments marked
/// "Don't show this again" are never eligible.
///
/// Within the chosen moment it prefers a strong photo that is *not* the cover — the timeline
/// already shows the cover, and rediscovery is the point.
public struct FoundForYouService: Sendable {
    public var configuration: FoundForYouConfiguration
    public var calendar: Calendar
    public var scorer: AssetScorer

    public init(configuration: FoundForYouConfiguration = .standard, calendar: Calendar, scorer: AssetScorer = AssetScorer()) {
        self.configuration = configuration
        self.calendar = calendar
        self.scorer = scorer
    }

    public func select(
        story: Story,
        assets: [AssetID: MemoryAsset],
        userStates: [MomentID: MomentUserState],
        isAvailable: (AssetID) -> Bool,
        now: Date
    ) -> FoundMemory? {
        let eligible = story.moments.filter { moment in
            guard moment.kind != .undated, let date = moment.startDate, date <= now else { return false }
            let state = userStates[moment.id]
            if state?.isHidden == true || state?.isExcludedFromSurfacing == true { return false }
            if let shown = state?.lastSurfacedAt, now.timeIntervalSince(shown) < configuration.cooldown { return false }
            return moment.featuredAssetIDs.contains(where: isAvailable)
        }

        let old = eligible.filter { moment in
            guard let date = moment.startDate else { return false }
            return now.timeIntervalSince(date) >= configuration.minimumAge
        }
        let pool = old.isEmpty ? eligible : old

        let describer = RelativeAgeDescriber(calendar: calendar)
        let dayKey = calendar.dateComponents([.year, .month, .day], from: now)
        let daySeed = "\(dayKey.year ?? 0)-\(dayKey.month ?? 0)-\(dayKey.day ?? 0)"

        var best: (moment: Moment, asset: MemoryAsset, score: Double)?
        for moment in pool {
            guard let picked = bestAsset(in: moment, assets: assets, userState: userStates[moment.id], isAvailable: isAvailable),
                  let date = moment.startDate else { continue }
            let asset = picked.asset
            let quality = picked.score
            let age = now.timeIntervalSince(date)
            var score = configuration.ageWeight * min(1, age / configuration.fullAgeScoreAfter)
            score += configuration.qualityWeight * max(0, min(1.5, quality))
            if describer.isNearAnniversary(date, now: now) { score += configuration.anniversaryBonus }
            if asset.isFavorite { score += configuration.favoriteBonus }
            score -= configuration.repeatPenalty * Double(userStates[moment.id]?.surfacedCount ?? 0)
            score += configuration.dailyVariation * FoundForYouService.jitter(seed: daySeed, key: moment.id.uuidString)

            if let current = best, score <= current.score { continue }
            best = (moment, asset, score)
        }

        guard let choice = best else { return nil }
        let date = choice.asset.creationDate ?? choice.moment.startDate
        return FoundMemory(
            momentID: choice.moment.id,
            assetID: choice.asset.id,
            captureDate: date,
            ageDescription: date.map { describer.describe($0, now: now) } ?? "",
            place: choice.moment.place
        )
    }

    /// Best non-cover photo if it's nearly as good as the cover; otherwise the cover.
    private func bestAsset(
        in moment: Moment,
        assets: [AssetID: MemoryAsset],
        userState: MomentUserState?,
        isAvailable: (AssetID) -> Bool
    ) -> (asset: MemoryAsset, score: Double)? {
        let candidates = moment.featuredAssetIDs
            .filter(isAvailable)
            .compactMap { assets[$0] }
            .filter { $0.kind == .photo && $0.analysis?.isUtility != true && !$0.isScreenshot }
        guard !candidates.isEmpty else { return nil }

        let scored = candidates.map { ($0, scorer.score($0)) }
            .sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        let cover = HeroSelector.resolvedHero(for: moment, userState: userState, isAvailable: isAvailable)
        let coverScore = scored.first { $0.0.id == cover }?.1 ?? scored[0].1
        if let alternative = scored.first(where: { $0.0.id != cover }), alternative.1 >= coverScore * 0.85 {
            return alternative
        }
        return scored.first { $0.0.id == cover } ?? scored[0]
    }

    /// Stable pseudo-random value in 0..<1 for (seed, key).
    static func jitter(seed: String, key: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(seed)|\(key)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 10_000) / 10_000
    }
}
