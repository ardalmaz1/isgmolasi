import Foundation

/// What the selection is for. Sets how many photos to choose and which shape suits it.
public enum IntelligenceTarget: Hashable, Sendable, Codable {
    case collage
    case story
    case book
    /// Any other use (recaps, Wrapped, future Movie): choose up to `limit`.
    case general(limit: Int)

    /// How many photos to choose: fewer than the lower bound is "not enough".
    public var range: ClosedRange<Int> {
        switch self {
        case .collage: CreationLimits.collage.lowerBound...CreationLimits.collagePreselection
        case .story: CreationLimits.story
        case .book: BookLimits.minimumPhotos...BookLimits.maximumPhotos
        case .general(let limit): 1...max(1, limit)
        }
    }

    /// The shape the lead photo fills best (a tall story card); nil when any shape works.
    public var preferredLeadOrientation: PhotoOrientation? {
        switch self {
        case .story: .portrait
        case .collage, .book, .general: nil
        }
    }
}

/// Weights of the internal ranking. Data, so they can be tuned without touching the logic.
///
/// The rank is never shown: it only decides which photo Relive tries first. Recency is
/// deliberately absent — an old memory is not a worse memory.
public struct RankingWeights: Hashable, Sendable, Codable {
    /// Favorited in Relive: the couple's own choice, the strongest signal.
    public var favorite: Double = 0.35
    /// The cover the user chose for the moment.
    public var userCover: Double = 0.3
    /// The cover Relive chose for the moment (already the moment's best photo).
    public var momentCover: Double = 0.1
    /// Suits the target's shape (a portrait lead for a story card).
    public var leadOrientation: Double = 0.1
    /// A known date and place make a page or card say more. Tiny on purpose.
    public var knownDate: Double = 0.02
    public var knownLocation: Double = 0.02

    // Diversity: how much each already-chosen photo with the same trait costs the next one.
    public var sameMoment: Double = 0.12
    public var sameDay: Double = 0.06
    public var samePlace: Double = 0.03
    /// Per photo of the same orientation beyond the other orientations' count.
    public var orientationImbalance: Double = 0.03
    /// Per photo of the same framing (people/scene) beyond the other's count.
    public var framingImbalance: Double = 0.04

    // Films (Memory Movie) only.
    /// Per already-chosen photo of the same scene shot again later that day (a look-alike).
    public var lookAlike: Double = 0.4
    /// A photo an earlier cut used, when "Make it for me" asks for a new one. Doubled while the
    /// new cut still repeats more than `maximumRepeatShare` of the earlier one.
    public var previouslyUsed: Double = 0.15
    /// How much of an earlier cut a new one may repeat when the source has enough alternatives.
    public var maximumRepeatShare: Double = 0.5

    public init() {}

    public static let standard = RankingWeights()
}

/// Ranks memories for creations. Deterministic: equal ranks fall back to capture order, then
/// identifier.
public struct MemoryRanker: Sendable {
    public var weights: RankingWeights

    public init(weights: RankingWeights = .standard) {
        self.weights = weights
    }

    /// The internal suitability of a candidate for `target`. Never shown to users.
    func suitability(_ candidate: MemoryCandidate, for target: IntelligenceTarget) -> Double {
        var value = candidate.quality
        if candidate.isFavorite { value += weights.favorite }
        if candidate.isUserCover { value += weights.userCover } else if candidate.isMomentCover { value += weights.momentCover }
        if candidate.captureDate != nil { value += weights.knownDate }
        if candidate.hasLocation { value += weights.knownLocation }
        return value
    }

    /// Suitability as the lead (cover, opener) of `target`.
    func leadSuitability(_ candidate: MemoryCandidate, for target: IntelligenceTarget) -> Double {
        var value = suitability(candidate, for: target)
        if let preferred = target.preferredLeadOrientation, candidate.orientation == preferred { value += weights.leadOrientation }
        return value
    }

    /// True when `lhs` ranks before `rhs`.
    func ranksBefore(_ lhs: MemoryCandidate, _ rhs: MemoryCandidate, by score: (MemoryCandidate) -> Double) -> Bool {
        let left = score(lhs), right = score(rhs)
        if abs(left - right) > 1e-9 { return left > right }
        if lhs.captureIndex != rhs.captureIndex { return lhs.captureIndex < rhs.captureIndex }
        return lhs.assetID < rhs.assetID
    }
}

/// Near-identical shots among the candidates, found with Relive's own similarity rules
/// (`DuplicateDetector.isSimilar`: same kind, close in time, close in look).
///
/// Cost: candidates are sorted by time and only compared within the similar-shot time window,
/// so this is close to linear for real photo sets (undated photos are compared with each other).
public struct SimilarityClusters: Sendable {
    /// Each clustered photo's cluster, keyed by the cluster's first (earliest) shot.
    public private(set) var clusterOf: [AssetID: AssetID] = [:]
    /// Members of each cluster, in the order they were taken.
    public private(set) var members: [AssetID: [AssetID]] = [:]

    public init(candidates: [MemoryCandidate], library: CreationLibrary, detector: DuplicateDetector = DuplicateDetector()) {
        let assets = candidates.compactMap { library.assets[$0.assetID] }
        let groups = detector.similarGroups(in: assets) { _ in 0 }
        for group in groups {
            guard let anchor = group.members.first else { continue }
            members[anchor] = group.members
            for id in group.members { clusterOf[id] = anchor }
        }
    }

    public var count: Int { members.count }
}

/// Chooses fewer, better photos: one per near-identical group, spread across moments, days,
/// places, shapes and framings — but only as much as the photos allow. A set that really is
/// one evening of portraits stays one evening of portraits.
public struct VisualDiversityEngine: Sendable {
    public var ranker: MemoryRanker

    public init(ranker: MemoryRanker = MemoryRanker()) {
        self.ranker = ranker
    }

    /// One representative per similarity cluster: a favorite if the cluster has one (a favorite
    /// is never dropped for a similar photo that merely ranks a little higher), otherwise the
    /// best. Returns the representatives and the photos they stand for.
    func representatives(_ candidates: [MemoryCandidate], clusters: SimilarityClusters, target: IntelligenceTarget)
        -> (kept: [MemoryCandidate], collapsed: [AssetID: AssetID]) {
        var byCluster: [AssetID: [MemoryCandidate]] = [:]
        var kept: [MemoryCandidate] = []
        for candidate in candidates {
            if let cluster = clusters.clusterOf[candidate.assetID] {
                byCluster[cluster, default: []].append(candidate)
            } else {
                kept.append(candidate)
            }
        }
        var collapsed: [AssetID: AssetID] = [:]
        for (_, group) in byCluster.sorted(by: { $0.key < $1.key }) {
            let favorites = group.filter { $0.isFavorite || $0.isUserCover }
            let pool = favorites.isEmpty ? group : favorites
            guard let best = pool.min(by: { ranker.ranksBefore($0, $1) { ranker.suitability($0, for: target) } }) else { continue }
            kept.append(best)
            for member in group where member.assetID != best.assetID {
                collapsed[member.assetID] = best.assetID
            }
        }
        return (kept, collapsed)
    }

    /// Greedy selection of up to `count` from `candidates` (already one per cluster), always
    /// including `required`. Each pick is the candidate with the best suitability after a small
    /// cost for every already-chosen photo it repeats (moment, day, place, shape, framing).
    func select(_ candidates: [MemoryCandidate], count: Int, required: [AssetID], target: IntelligenceTarget) -> [MemoryCandidate] {
        guard count > 0 else { return [] }
        var remaining = candidates
        var chosen: [MemoryCandidate] = []
        var tally = Tally()

        for id in required {
            guard chosen.count < count, let index = remaining.firstIndex(where: { $0.assetID == id }) else { continue }
            let candidate = remaining.remove(at: index)
            chosen.append(candidate)
            tally.add(candidate)
        }
        if remaining.count + chosen.count <= count {
            return chosen + remaining
        }
        let weights = ranker.weights
        while chosen.count < count, !remaining.isEmpty {
            var bestIndex = 0
            var bestScore = -Double.infinity
            for (index, candidate) in remaining.enumerated() {
                let score = ranker.suitability(candidate, for: target) - tally.cost(of: candidate, weights: weights)
                let current = remaining[bestIndex]
                if score > bestScore + 1e-9
                    || (abs(score - bestScore) <= 1e-9 && (candidate.captureIndex, candidate.assetID) < (current.captureIndex, current.assetID)) {
                    bestScore = score
                    bestIndex = index
                }
            }
            let pick = remaining.remove(at: bestIndex)
            chosen.append(pick)
            tally.add(pick)
        }
        return chosen
    }

    /// A film's selection: like `select`, plus
    /// - coverage: when the source spans several days (or, in one day, several moments), the
    ///   best photo of each is chosen first — evenly spread when there are more days than photos
    ///   — so a long trip isn't told from one afternoon;
    /// - look-alikes: each already-chosen photo of the same scene costs `weights.lookAlike`;
    /// - a new cut: photos in `avoiding` cost `weights.previouslyUsed`, raised until the new cut
    ///   repeats at most `weights.maximumRepeatShare` of the old one (or nothing changes).
    /// Deterministic.
    func selectForFilm(
        _ candidates: [MemoryCandidate],
        count: Int,
        required: [AssetID],
        target: IntelligenceTarget,
        avoiding: Set<AssetID>,
        looksAlike: (MemoryCandidate, MemoryCandidate) -> Bool,
        coversDays: Bool
    ) -> [MemoryCandidate] {
        guard count > 0 else { return [] }
        if candidates.count <= count {
            return candidates
        }
        var penalty = ranker.weights.previouslyUsed
        var result = filmPass(candidates, count: count, required: required, target: target, avoiding: avoiding, penalty: penalty, looksAlike: looksAlike, coversDays: coversDays)
        guard !avoiding.isEmpty else { return result }
        let allowed = Int((Double(min(count, avoiding.count)) * ranker.weights.maximumRepeatShare).rounded(.down))
        for _ in 0..<4 {
            let repeated = result.filter { avoiding.contains($0.assetID) }.count
            guard repeated > allowed else { break }
            penalty *= 2
            let next = filmPass(candidates, count: count, required: required, target: target, avoiding: avoiding, penalty: penalty, looksAlike: looksAlike, coversDays: coversDays)
            if next.map(\.assetID) == result.map(\.assetID) { break }
            result = next
        }
        return result
    }

    private func filmPass(
        _ candidates: [MemoryCandidate],
        count: Int,
        required: [AssetID],
        target: IntelligenceTarget,
        avoiding: Set<AssetID>,
        penalty: Double,
        looksAlike: (MemoryCandidate, MemoryCandidate) -> Bool,
        coversDays: Bool
    ) -> [MemoryCandidate] {
        var remaining = candidates
        var chosen: [MemoryCandidate] = []
        var tally = Tally()
        let weights = ranker.weights

        func score(_ candidate: MemoryCandidate) -> Double {
            var value = ranker.suitability(candidate, for: target) - tally.cost(of: candidate, weights: weights)
            if avoiding.contains(candidate.assetID) { value -= penalty }
            let alike = chosen.reduce(0) { $0 + (looksAlike(candidate, $1) ? 1 : 0) }
            value -= weights.lookAlike * Double(alike)
            return value
        }
        func take(_ index: Int) {
            let pick = remaining.remove(at: index)
            chosen.append(pick)
            tally.add(pick)
        }
        func bestIndex(among indices: [Int]) -> Int? {
            var best: (index: Int, score: Double)?
            for index in indices {
                let candidate = remaining[index]
                let value = score(candidate)
                if let current = best {
                    let other = remaining[current.index]
                    if value > current.score + 1e-9
                        || (abs(value - current.score) <= 1e-9 && (candidate.captureIndex, candidate.assetID) < (other.captureIndex, other.assetID)) {
                        best = (index, value)
                    }
                } else {
                    best = (index, value)
                }
            }
            return best?.index
        }

        for id in required {
            guard chosen.count < count, let index = remaining.firstIndex(where: { $0.assetID == id }) else { continue }
            take(index)
        }

        // Coverage: one photo from each day (or each moment of a single day).
        if coversDays {
            let days = Set(remaining.compactMap(\.day))
            let groupKey: (MemoryCandidate) -> String? = days.count > 1
                ? { $0.day.map { "\($0.year)-\($0.month)-\($0.day)" } }
                : { $0.momentID?.uuidString }
            var groups: [String] = []
            var seen = Set<String>()
            for candidate in remaining.sorted(by: { ($0.captureIndex, $0.assetID) < ($1.captureIndex, $1.assetID) }) {
                if let key = groupKey(candidate), seen.insert(key).inserted { groups.append(key) }
            }
            let covered = Set(chosen.compactMap(groupKey))
            groups.removeAll { covered.contains($0) }
            // Leave room for the strongest photos: coverage takes at most two thirds of the cut.
            let room = max(0, (count * 2) / 3 - chosen.count)
            if groups.count > 1, room > 0 {
                let picked = groups.count <= room ? groups : stride(from: 0, to: room, by: 1).map { groups[$0 * groups.count / room] }
                for key in picked where chosen.count < count {
                    let indices = remaining.indices.filter { groupKey(remaining[$0]) == key }
                    if let index = bestIndex(among: indices) { take(index) }
                }
            }
        }

        while chosen.count < count, !remaining.isEmpty {
            guard let index = bestIndex(among: Array(remaining.indices)) else { break }
            take(index)
        }
        return chosen
    }

    /// How often each trait already appears among the chosen photos.
    struct Tally {
        var moments: [MomentID: Int] = [:]
        var days: [DayKey: Int] = [:]
        var places: [String: Int] = [:]
        var orientations: [PhotoOrientation: Int] = [:]
        var framings: [MemoryCandidate.Framing: Int] = [:]

        mutating func add(_ candidate: MemoryCandidate) {
            if let moment = candidate.momentID { moments[moment, default: 0] += 1 }
            if let day = candidate.day { days[day, default: 0] += 1 }
            if let place = candidate.place?.comparisonKey { places[place, default: 0] += 1 }
            if let orientation = candidate.orientation { orientations[Self.shape(orientation), default: 0] += 1 }
            if let framing = candidate.framing { framings[framing, default: 0] += 1 }
        }

        func cost(of candidate: MemoryCandidate, weights: RankingWeights) -> Double {
            var cost = 0.0
            if let moment = candidate.momentID { cost += weights.sameMoment * Double(moments[moment] ?? 0) }
            if let day = candidate.day { cost += weights.sameDay * Double(days[day] ?? 0) }
            if let place = candidate.place?.comparisonKey { cost += weights.samePlace * Double(places[place] ?? 0) }
            if let orientation = candidate.orientation {
                let shape = Self.shape(orientation)
                let same = orientations[shape] ?? 0
                let others = orientations.filter { $0.key != shape }.values.reduce(0, +)
                cost += weights.orientationImbalance * Double(max(0, same - others))
            }
            if let framing = candidate.framing {
                let same = framings[framing] ?? 0
                let others = framings.filter { $0.key != framing }.values.reduce(0, +)
                cost += weights.framingImbalance * Double(max(0, same - others))
            }
            return cost
        }

        /// Square counts with portrait (both fill a tall frame); panoramas with landscape.
        static func shape(_ orientation: PhotoOrientation) -> PhotoOrientation {
            switch orientation {
            case .portrait, .square: .portrait
            case .landscape, .panorama: .landscape
            }
        }
    }
}
