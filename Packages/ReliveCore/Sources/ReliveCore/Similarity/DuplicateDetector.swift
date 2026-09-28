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
    public func duplicateGroups(in assets: [MemoryAsset]) -> [DuplicateGroup] {
        let candidates = assets.filter { $0.kind == .photo && $0.analysis?.fingerprint != nil }
        guard candidates.count > 1 else { return [] }

        var sets = UnionFind(count: candidates.count)
        for lhs in 0..<candidates.count {
            for rhs in (lhs + 1)..<candidates.count where isDuplicate(candidates[lhs], candidates[rhs]) {
                sets.union(lhs, rhs)
            }
        }

        return sets.groups().map { indices in
            let members = indices.map { candidates[$0] }
            let primary = members.max(by: DuplicateDetector.primaryPreference) ?? members[0]
            let copies = members.filter { $0.id != primary.id }.map(\.id).sorted()
            return DuplicateGroup(primary: primary.id, copies: copies)
        }
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
        let hashDistance = left.hashDistance(to: right)
        if let hashDistance, hashDistance > configuration.duplicateHashDistanceWithFeatures {
            return false
        }
        if let featureDistance = left.featureDistance(to: right) {
            return featureDistance <= configuration.duplicateFeatureDistance
        }
        guard let hashDistance, isHashReliable(left), isHashReliable(right) else { return false }
        return hashDistance <= configuration.duplicateHashDistance
    }

    /// The copy we keep: favorite, then located, then higher resolution, then earlier capture.
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
    /// `score` ranks members; the highest-scoring one becomes the representative.
    public func similarGroups(in assets: [MemoryAsset], score: (MemoryAsset) -> Double) -> [SimilarGroup] {
        let sorted = assets.sorted(by: MetadataProcessor.chronological)
        guard sorted.count > 1 else { return [] }

        var sets = UnionFind(count: sorted.count)
        for lhs in 0..<sorted.count {
            for rhs in (lhs + 1)..<sorted.count {
                if let start = sorted[lhs].creationDate, let end = sorted[rhs].creationDate,
                   end.timeIntervalSince(start) > configuration.similarMaximumTimeGap {
                    break // sorted by time: everything further is even later
                }
                if isSimilar(sorted[lhs], sorted[rhs]) {
                    sets.union(lhs, rhs)
                }
            }
        }

        return sets.groups().map { indices in
            let members = indices.map { sorted[$0] }
            let representative = members.max { lhs, rhs in
                let left = score(lhs), right = score(rhs)
                return left == right ? lhs.id > rhs.id : left < right
            } ?? members[0]
            return SimilarGroup(representative: representative.id, members: members.map(\.id))
        }
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
        guard let hashDistance = left.hashDistance(to: right), isHashReliable(left), isHashReliable(right) else {
            return false
        }
        return hashDistance <= configuration.similarHashDistance
    }

    private func isHashReliable(_ fingerprint: VisualFingerprint) -> Bool {
        guard let contrast = fingerprint.contrast else { return true }
        return contrast >= configuration.minimumReliableContrast
    }
}
