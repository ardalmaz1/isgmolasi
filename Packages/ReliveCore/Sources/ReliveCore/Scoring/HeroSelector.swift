import Foundation

/// Chooses each moment's cover image.
///
/// The algorithm only makes the *default* choice: a cover the user picked
/// (`MomentUserState.heroOverrideAssetID`) always wins at display time, as long as that asset
/// still exists — see `resolvedHero`.
public struct HeroSelector: Sendable {
    public var scorer: AssetScorer

    public init(scorer: AssetScorer = AssetScorer()) {
        self.scorer = scorer
    }

    /// Picks the best asset among `candidates`. `similarShotCounts` tells how many near-identical
    /// shots each candidate stands for. Ties resolve to the earlier asset for stable output.
    public func selectHero(among candidates: [MemoryAsset], similarShotCounts: [AssetID: Int] = [:]) -> AssetID? {
        var best: (id: AssetID, score: Double, date: Date)?
        for asset in candidates {
            let score = scorer.score(asset, similarShotCount: similarShotCounts[asset.id] ?? 0)
            let date = asset.creationDate ?? .distantFuture
            if let current = best {
                if score > current.score + 1e-9 || (abs(score - current.score) <= 1e-9 && date < current.date) {
                    best = (asset.id, score, date)
                }
            } else {
                best = (asset.id, score, date)
            }
        }
        return best?.id
    }

    /// The cover to display: the user's choice if still available, otherwise the algorithmic
    /// choice if available, otherwise the first available featured asset.
    public static func resolvedHero(
        for moment: Moment,
        userState: MomentUserState?,
        isAvailable: (AssetID) -> Bool
    ) -> AssetID? {
        if let override = userState?.heroOverrideAssetID, moment.assetIDs.contains(override), isAvailable(override) {
            return override
        }
        if let hero = moment.heroAssetID, isAvailable(hero) {
            return hero
        }
        return moment.featuredAssetIDs.first(where: isAvailable) ?? moment.assetIDs.first(where: isAvailable)
    }
}
