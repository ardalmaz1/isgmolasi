import Foundation

/// Finds duplicate copies across the whole selection and near-identical shots inside a moment.
///
/// Nothing is ever deleted. Duplicates and similar shots are only collapsed behind a
/// "Show similar" affordance so the same picture doesn't appear twice in a row.
///
/// - **Duplicates** (global): the same image saved twice, e.g. an original and its
///   WhatsApp-compressed copy saved days later without location. The copy would otherwise
///   create a phantom moment on the day it was saved, so copies are removed from clustering
///   and attached to the moment of their original.
/// - **Similar shots** (per moment): bursts and "one more" photos taken within minutes that
///   look nearly the same. The best one stays featured; favorites always stay featured.
///
/// Both use *star* grouping: every member must match the group's anchor directly. Transitive
/// grouping (A≈B, B≈C ⇒ A, B, C together) chains loosely related photos into one huge group and
/// hides memories that don't look alike at all — the worst possible failure for this product.
public struct DuplicateDetector: Sendable {
    public struct DuplicateGroup: Hashable, Sendable {
        public var primary: AssetID
        public var copies: [AssetID]
    }

    public struct SimilarGroup: Hashable, Sendable {
        public var representative: AssetID
        public var members: [AssetID]
    }

    public var configuration: SimilarityConfiguration

    public init(configuration: SimilarityConfiguration = .standard) {
        self.configuration = configuration
    }

    // MARK: - Duplicates

    /// Groups copies of the same image. Videos are never considered duplicates.
    ///
    /// Candidates are visited from the best keeper to the worst (favorite, located, highest
    /// resolution, earliest), so each group's anchor is the copy worth keeping.
    public func duplicateGroups(in assets: [MemoryAsset]) -> [DuplicateGroup] {
        let candidates = assets
            .filter { $0.kind == .photo && $0.analysis?.fingerprint != nil }
            .sorted { DuplicateDetector.primaryPreference($1, $0) }
        guard candidates.count > 1 else { return [] }

        var assigned = Set<Int>()
        var groups: [DuplicateGroup] = []
        for anchor in candidates.indices where !assigned.contains(anchor) {
            var copies: [AssetID] = []
            for other in (anchor + 1)..<candidates.count where !assigned.contains(other) {
                if isDuplicate(candidates[anchor], candidates[other]) {
                    copies.append(candidates[other].id)
                    assigned.insert(other)
                }
            }
            if !copies.isEmpty {
                assigned.insert(anchor)
                groups.append(DuplicateGroup(primary: candidates[anchor].id, copies: copies.sorted()))
            }
        }
        return groups.sorted { $0.primary < $1.primary }
    }

    public func isDuplicate(_ lhs: MemoryAsset, _ rhs: MemoryAsset) -> Bool {
        guard lhs.kind == .photo, rhs.kind == .photo,
              let left = lhs.analysis?.fingerprint, let right = rhs.analysis?.fingerprint else { return false }

        if let leftRatio = lhs.aspectRatio, let rightRatio = rhs.aspectRatio {
            // Compare long/short side so a missing orientation flag doesn't matter.
            let a = max(leftRatio, 1 / leftRatio)
            let b = max(rightRatio, 1 / rightRatio)
            guard abs(a - b) / max(a, b) <= configuration.duplicateAspectRatioTolerance else { return false }
        }

        // The 64-bit hash comparison is far cheaper than the embedding distance, so it goes first.
        let hashesUsable = isHashReliable(left) && isHashReliable(right)
        let hashDistance = hashesUsable ? left.hashDistance(to: right) : nil
        if let hashDistance, hashDistance > configuration.duplicateHashDistanceWithFeatures {
            return false
        }
        if let featureDistance = left.featureDistance(to: right) {
            // Both signals agree (the hash gate above already passed)...
            if hashesUsable { return featureDistance <= configuration.duplicateFeatureDistance }
            // ...or, when the hashes say nothing, the embeddings alone must be twice as close.
            return featureDistance <= configuration.duplicateFeatureDistance / 2
        }
        // Without embeddings a 64-bit hash can't tell "same photo" from "same composition"
        // (two sunsets over the same horizon), so also require the signature of a re-saved copy.
        guard let hashDistance, hashDistance <= configuration.duplicateHashDistance else { return false }
        return looksLikeResavedCopy(lhs, rhs)
    }

    /// A messaging-app or screenshot re-save is noticeably smaller, or has lost its location.
    func looksLikeResavedCopy(_ lhs: MemoryAsset, _ rhs: MemoryAsset) -> Bool {
        if (lhs.location == nil) != (rhs.location == nil) { return true }
        let smaller = min(lhs.megapixels, rhs.megapixels)
        let larger = max(lhs.megapixels, rhs.megapixels)
        guard larger > 0 else { return false }
        return smaller / larger <= configuration.resavedCopyMaximumResolutionRatio
    }

    /// The copy we keep: favorite, then located, then higher resolution, then earlier capture.
    /// Returns true when `lhs` is the *worse* keeper.
    static func primaryPreference(_ lhs: MemoryAsset, _ rhs: MemoryAsset) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return !lhs.isFavorite }
        if (lhs.location != nil) != (rhs.location != nil) { return lhs.location == nil }
        if lhs.megapixels != rhs.megapixels { return lhs.megapixels < rhs.megapixels }
        let left = lhs.creationDate ?? .distantFuture
        let right = rhs.creationDate ?? .distantFuture
        if left != right { return left > right }
        return lhs.id > rhs.id
    }

    // MARK: - Similar shots

    /// Groups near-identical shots taken close together. `assets` should belong to one moment.
    /// Each group is anchored on its earliest shot; members are similar to that shot and taken
    /// within `similarMaximumTimeGap` of it. `score` picks the representative.
    public func similarGroups(in assets: [MemoryAsset], score: (MemoryAsset) -> Double) -> [SimilarGroup] {
        let sorted = assets.sorted(by: MetadataProcessor.chronological)
        guard sorted.count > 1 else { return [] }

        var assigned = Set<Int>()
        var groups: [SimilarGroup] = []
        for anchor in sorted.indices where !assigned.contains(anchor) {
            var memberIndices = [anchor]
            for other in (anchor + 1)..<sorted.count {
                if let start = sorted[anchor].creationDate, let end = sorted[other].creationDate,
                   end.timeIntervalSince(start) > configuration.similarMaximumTimeGap {
                    break // sorted by time: everything further is even later
                }
                if !assigned.contains(other) && isSimilar(sorted[anchor], sorted[other]) {
                    memberIndices.append(other)
                }
            }
            guard memberIndices.count > 1 else { continue }
            assigned.formUnion(memberIndices)

            let members = memberIndices.map { sorted[$0] }
            let representative = members.max { lhs, rhs in
                let left = score(lhs), right = score(rhs)
                return left == right ? lhs.id > rhs.id : left < right
            } ?? members[0]
            groups.append(SimilarGroup(representative: representative.id, members: members.map(\.id)))
        }
        return groups
    }

    public func isSimilar(_ lhs: MemoryAsset, _ rhs: MemoryAsset) -> Bool {
        guard lhs.kind == rhs.kind,
              let left = lhs.analysis?.fingerprint, let right = rhs.analysis?.fingerprint else { return false }
        if let start = lhs.creationDate, let end = rhs.creationDate,
           abs(end.timeIntervalSince(start)) > configuration.similarMaximumTimeGap {
            return false
        }
        if let featureDistance = left.featureDistance(to: right) {
            return featureDistance <= configuration.similarFeatureDistance
        }
        guard isHashReliable(left), isHashReliable(right), let hashDistance = left.hashDistance(to: right) else {
            return false
        }
        return hashDistance <= configuration.similarHashDistance
    }

    /// A perceptual hash only means something if the image has contrast and the hash itself
    /// carries information. Flat images (sky, wall, night) hash to nearly all zeros, and any two
    /// of them would otherwise look like copies of each other.
    private func isHashReliable(_ fingerprint: VisualFingerprint) -> Bool {
        guard let hash = fingerprint.differenceHash else { return false }
        if let contrast = fingerprint.contrast, contrast < configuration.minimumReliableContrast {
            return false
        }
        let bits = hash.nonzeroBitCount
        return bits >= configuration.minimumHashBits && bits <= 64 - configuration.minimumHashBits
    }
}
