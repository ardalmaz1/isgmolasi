import Foundation

/// Keeps user state attached when a story is regenerated (e.g. after adding memories).
///
/// Moment ids are derived from their first asset, so adding an earlier photo to a moment would
/// otherwise change its id and orphan its note. The reconciler matches each new moment to the
/// previous moment it overlaps most and reuses the previous id.
///
/// Matching: overlap coefficient |A ∩ B| / min(|A|, |B|) ≥ `minimumOverlap`, greedily from the
/// strongest overlap, one-to-one. States of previous moments that no longer match anything
/// (all their photos were removed) are kept, so they come back if the photos do.
public struct MomentReconciler: Sendable {
    public var minimumOverlap: Double

    public init(minimumOverlap: Double = 0.5) {
        self.minimumOverlap = minimumOverlap
    }

    public func reconcile(new story: Story, previous: Story) -> Story {
        guard !previous.moments.isEmpty, !story.moments.isEmpty else { return story }

        let previousSets = previous.moments.map { Set($0.assetIDs) }
        var previousIndexByAsset: [AssetID: [Int]] = [:]
        for (index, set) in previousSets.enumerated() {
            for asset in set { previousIndexByAsset[asset, default: []].append(index) }
        }

        struct Candidate {
            let newIndex: Int
            let previousIndex: Int
            let overlap: Double
            let shared: Int
        }
        var candidates: [Candidate] = []
        for (newIndex, moment) in story.moments.enumerated() {
            let newSet = Set(moment.assetIDs)
            var sharedCounts: [Int: Int] = [:]
            for asset in newSet {
                for previousIndex in previousIndexByAsset[asset] ?? [] {
                    sharedCounts[previousIndex, default: 0] += 1
                }
            }
            for (previousIndex, shared) in sharedCounts {
                let smaller = min(newSet.count, previousSets[previousIndex].count)
                let overlap = smaller > 0 ? Double(shared) / Double(smaller) : 0
                if overlap >= minimumOverlap {
                    candidates.append(Candidate(newIndex: newIndex, previousIndex: previousIndex, overlap: overlap, shared: shared))
                }
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
            if lhs.shared != rhs.shared { return lhs.shared > rhs.shared }
            if lhs.newIndex != rhs.newIndex { return lhs.newIndex < rhs.newIndex }
            return lhs.previousIndex < rhs.previousIndex
        }

        var idMap: [MomentID: MomentID] = [:]
        var usedNew = Set<Int>()
        var usedPrevious = Set<Int>()
        var takenIDs = Set<MomentID>()
        for candidate in candidates where !usedNew.contains(candidate.newIndex) && !usedPrevious.contains(candidate.previousIndex) {
            usedNew.insert(candidate.newIndex)
            usedPrevious.insert(candidate.previousIndex)
            let previousID = previous.moments[candidate.previousIndex].id
            idMap[story.moments[candidate.newIndex].id] = previousID
            takenIDs.insert(previousID)
        }

        var result = story
        for index in result.moments.indices {
            let original = result.moments[index]
            guard let mapped = idMap[original.id] else {
                // A fresh moment whose derived id happens to equal a reused one keeps its own id
                // only if that doesn't collide.
                if takenIDs.contains(original.id) {
                    result.moments[index] = original.withID(StableIdentifier.uuid(namespace: "rekey", key: original.id.uuidString))
                }
                continue
            }
            result.moments[index] = original.withID(mapped)
        }
        let finalIDs = Dictionary(uniqueKeysWithValues: zip(story.moments.map(\.id), result.moments.map(\.id)))
        for index in result.chapters.indices {
            result.chapters[index].momentIDs = result.chapters[index].momentIDs.map { finalIDs[$0] ?? $0 }
        }
        return result
    }
}

extension Moment {
    func withID(_ id: MomentID) -> Moment {
        Moment(
            id: id,
            kind: kind,
            assetIDs: assetIDs,
            featuredAssetIDs: featuredAssetIDs,
            similarAssetIDs: similarAssetIDs,
            duplicateAssetIDs: duplicateAssetIDs,
            heroAssetID: heroAssetID,
            startDate: startDate,
            endDate: endDate,
            centroid: centroid,
            place: place,
            title: title,
            chapterID: chapterID
        )
    }
}
