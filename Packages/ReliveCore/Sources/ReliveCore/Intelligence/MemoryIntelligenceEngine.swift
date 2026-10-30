import Foundation

/// What to plan: which memories to consider, for what, and what the user already decided.
public struct IntelligenceRequest: Hashable, Sendable {
    public enum Mode: String, Hashable, Sendable, Codable {
        /// Relive chooses from the pool (a moment, trip, month, year, favorites).
        case automatic
        /// The user chose these photos. They are kept — never swapped for others; Relive only
        /// leaves out what can't be shown, suggests an order and reports near-duplicates.
        case userSelected
    }

    public var pool: [AssetID]
    public var target: IntelligenceTarget
    public var mode: Mode
    /// Always included (e.g. the moment's cover).
    public var required: [AssetID]
    /// The user's own choice of lead (a book's cover). Wins whenever it is selected.
    public var preferredLead: AssetID?
    /// Words the user wrote for the title.
    public var userTitle: String?
    /// Overrides the target's maximum.
    public var limit: Int?
    /// Overrides the target's minimum: near-identical photos fill in up to it when there aren't
    /// enough distinct ones (a creation that needs three photos still gets three).
    public var minimum: Int?
    /// A film's selection (Memory Movie): look-alike photos — the same scene shot again later
    /// the same day — cost more, and the source's days (or moments) are each covered first.
    public var isFilm: Bool = false
    /// Photos an earlier cut used ("Make it for me" again): they cost more, so a large source
    /// gives a meaningfully different set. A small source may still give the same photos.
    public var avoiding: Set<AssetID> = []

    public init(
        pool: [AssetID],
        target: IntelligenceTarget,
        mode: Mode = .automatic,
        required: [AssetID] = [],
        preferredLead: AssetID? = nil,
        userTitle: String? = nil,
        limit: Int? = nil,
        minimum: Int? = nil
    ) {
        self.pool = pool
        self.target = target
        self.mode = mode
        self.required = required
        self.preferredLead = preferredLead
        self.userTitle = userTitle
        self.limit = limit
        self.minimum = minimum
    }
}

/// The reusable result: what to use, what leads, in what order, what's true about it, and what
/// it suits. Holds identifiers and facts only — no pixels, notes or coordinates.
public struct MemorySelectionPlan: Hashable, Sendable, Codable {
    public enum Status: Hashable, Sendable, Codable {
        case ready
        /// Fewer usable memories than the target needs.
        case insufficient(available: Int, required: Int)
    }

    /// Why the lead leads.
    public enum LeadReason: String, Hashable, Sendable, Codable {
        /// The user chose it (e.g. a book's cover).
        case userChoice
        /// The user chose it as its moment's cover.
        case userCover
        /// Favorited in Relive.
        case favorite
        /// Its moment's cover.
        case momentCover
        /// The best photo by Relive's own image signals.
        case quality
        case none
    }

    /// Something the plan couldn't do or doesn't know — said, not hidden.
    public enum Limitation: Hashable, Sendable, Codable {
        /// No longer in the photo library.
        case missing(Int)
        /// In hidden moments.
        case hidden(Int)
        /// Videos, screenshots, receipts.
        case notUsable(Int)
        /// Selected memories without a capture date (they stay undated).
        case undated(Int)
        /// Selected memories without a known place (they stay unplaced).
        case unplaced(Int)
        /// Near-identical photos used anyway, to reach the target's minimum.
        case repeatedSimilar(Int)
    }

    public var target: IntelligenceTarget
    public var mode: IntelligenceRequest.Mode
    public var status: Status
    /// Memories considered.
    public var sourceCount: Int
    /// What to use. Automatic: chronological. User-selected: the user's order.
    public var selected: [AssetID]
    public var lead: AssetID?
    public var leadReason: LeadReason
    /// Good photos that weren't chosen, best first — for "Make it for me" variations and swaps.
    public var alternates: [AssetID]
    /// Re-saved copies left out.
    public var excludedDuplicates: [AssetID]
    /// Near-identical photos left out, each with the photo that stands for it.
    public var collapsedSimilar: [AssetID: AssetID]
    public var similarityClusterCount: Int
    /// Near-identical pairs among a user's own selection (reported, never removed).
    public var nearDuplicateSelections: [[AssetID]]
    public var period: PeriodDescriptor
    public var title: FactualTitle
    public var sequence: MemorySequence
    public var recommendations: [CreationRecommendation]
    public var limitations: [Limitation]

    public var isReady: Bool { status == .ready }

    /// One DEBUG log line: counts and reasons only — no identifiers, places or coordinates.
    public var diagnosticsLine: String {
        let recommendations = self.recommendations.map(\.kind.rawValue).joined(separator: ",")
        let limitations = self.limitations.map(\.code).joined(separator: ",")
        return "intelligence_plan target=\(target.code) mode=\(mode.rawValue) source=\(sourceCount) selected=\(selected.count)"
            + " duplicatesRemoved=\(excludedDuplicates.count) similarCollapsed=\(collapsedSimilar.count)"
            + " similarityClusters=\(similarityClusterCount) sections=\(sequence.sections.count) period=\(period.code)"
            + " leadReason=\(leadReason.rawValue) recommendations=[\(recommendations)] limitations=[\(limitations)]"
            + (isReady ? "" : " status=insufficient")
    }
}

/// "Given a group of Yuvi memories, produce a factual, reusable creation plan."
///
/// Deterministic, on-device and pixel-free: it reads only the story and the analysis Relive
/// already has (`AssetScorer` signals, similarity fingerprints, moments, covers, favorites).
/// See docs/MEMORY_INTELLIGENCE.md.
public struct MemoryIntelligenceEngine: Sendable {
    public var library: CreationLibrary
    public var ranker: MemoryRanker
    public var detector: DuplicateDetector
    public var locale: Locale
    /// Whether plans go to the DEBUG diagnostics sink (off for quick lookups like a cover).
    public var logsDiagnostics = true

    public init(
        library: CreationLibrary,
        ranker: MemoryRanker = MemoryRanker(),
        detector: DuplicateDetector = DuplicateDetector(),
        locale: Locale = Locale(identifier: "en_US")
    ) {
        self.library = library
        self.ranker = ranker
        self.detector = detector
        self.locale = locale
    }

    // MARK: - Planning

    /// A plan for a creation source: automatic for moments, trips, months, years and favorites
    /// (the moment's cover is always included); the user's own photos for `.photos`.
    public func plan(for source: CreationSource, target: IntelligenceTarget, limit: Int? = nil, minimum: Int? = nil) -> MemorySelectionPlan {
        plan(for: source, target: target, limit: limit, minimum: minimum, isFilm: false, avoiding: [])
    }

    /// The same, for a film (`isFilm`) and/or steering away from an earlier cut (`avoiding`).
    public func plan(for source: CreationSource, target: IntelligenceTarget, limit: Int? = nil, minimum: Int? = nil, isFilm: Bool, avoiding: Set<AssetID>) -> MemorySelectionPlan {
        var request: IntelligenceRequest
        switch source {
        case .photos(let ids):
            request = IntelligenceRequest(pool: ids, target: target, mode: .userSelected, limit: limit, minimum: minimum)
        case .moment(let id):
            // A new cut needn't open on the same cover: the cover is required only the first time.
            let lead = avoiding.isEmpty ? library.story.moment(id: id).flatMap(library.lead(of:)) : nil
            request = IntelligenceRequest(pool: library.availablePhotos(for: source), target: target, required: lead.map { [$0] } ?? [], limit: limit, minimum: minimum)
        default:
            request = IntelligenceRequest(pool: library.availablePhotos(for: source), target: target, limit: limit, minimum: minimum)
        }
        request.isFilm = isFilm
        request.avoiding = avoiding
        return plan(request)
    }

    public func plan(_ request: IntelligenceRequest) -> MemorySelectionPlan {
        let all = MemoryCandidate.build(request.pool, library: library)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.assetID, $0) })

        // 1. What can be shown at all.
        let missing = all.filter { !$0.isAvailable }
        let available = all.filter(\.isAvailable)
        let notUsable = available.filter { !$0.isUsable }
        let usable = available.filter(\.isUsable)
        // Hidden memories, and memories the couple asked Relive not to suggest, are never chosen
        // automatically (photos the user picked are kept).
        let hidden = request.mode == .automatic ? usable.filter { $0.isHidden || $0.isExcludedFromSuggestions } : []
        var shown = request.mode == .automatic ? usable.filter { !$0.isHidden && !$0.isExcludedFromSuggestions } : usable

        // 2. Re-saved copies: known from the story, and checked for photos from outside it.
        var duplicates = Set(shown.filter(\.isDuplicateCopy).map(\.assetID))
        duplicates.formUnion(outsideStoryDuplicates(shown))
        let duplicateList = shown.filter { duplicates.contains($0.assetID) }.map(\.assetID)

        let clusters = SimilarityClusters(candidates: shown.filter { !duplicates.contains($0.assetID) }, library: library, detector: detector)
        let maximum = max(0, request.limit ?? request.target.range.upperBound)
        let minimum = min(request.minimum ?? request.target.range.lowerBound, maximum)
        var chosen: [MemoryCandidate]
        var collapsed: [AssetID: AssetID] = [:]
        var alternates: [MemoryCandidate] = []
        var nearDuplicateSelections: [[AssetID]] = []
        var repeated = 0
        let diversity = VisualDiversityEngine(ranker: ranker)

        switch request.mode {
        case .userSelected:
            // The user's photos, in their order. Nothing is swapped or silently dropped.
            chosen = Array(shown.prefix(maximum))
            let chosenIDs = Set(chosen.map(\.assetID))
            nearDuplicateSelections = clusters.members.values
                .map { $0.filter(chosenIDs.contains) }
                .filter { $0.count > 1 }
                .sorted { $0[0] < $1[0] }
        case .automatic:
            shown.removeAll { duplicates.contains($0.assetID) }
            var (representatives, folded) = diversity.representatives(shown, clusters: clusters, target: request.target)
            // A required photo stands for its cluster — except over a favorite, when it is only
            // Relive's own choice (e.g. the moment's automatic cover): then the favorite stands
            // for both, and counts as the required photo.
            for id in request.required {
                guard let representative = folded[id], let candidate = byID[id] else { continue }
                if let standing = byID[representative], standing.isFavorite || standing.isUserCover,
                   !candidate.isFavorite, !candidate.isUserCover {
                    continue
                }
                representatives.removeAll { $0.assetID == representative }
                representatives.append(candidate)
                folded[id] = nil
                folded[representative] = id
                for (member, stand) in folded where stand == representative { folded[member] = id }
            }
            collapsed = folded
            let required = request.required.map { folded[$0] ?? $0 }
            if request.isFilm || !request.avoiding.isEmpty {
                chosen = diversity.selectForFilm(
                    representatives,
                    count: maximum,
                    required: required,
                    target: request.target,
                    avoiding: request.avoiding,
                    looksAlike: request.isFilm ? lookAlikeTest() : { _, _ in false },
                    coversDays: request.isFilm
                )
            } else {
                chosen = diversity.select(representatives, count: maximum, required: required, target: request.target)
            }

            // Too few distinct photos: near-identical ones may fill in (said in the limitations).
            if chosen.count < minimum {
                let extra = shown.filter { collapsed[$0.assetID] != nil }
                    .sorted { ranker.ranksBefore($0, $1) { ranker.suitability($0, for: request.target) } }
                for candidate in extra.prefix(minimum - chosen.count) {
                    chosen.append(candidate)
                    collapsed[candidate.assetID] = nil
                    repeated += 1
                }
            }
            let chosenIDs = Set(chosen.map(\.assetID))
            alternates = representatives.filter { !chosenIDs.contains($0.assetID) }
                .sorted { ranker.ranksBefore($0, $1) { ranker.suitability($0, for: request.target) } }
            chosen.sort { ($0.captureIndex, $0.assetID) < ($1.captureIndex, $1.assetID) }
        }

        // 3. The lead, then the sequence and what's true about it.
        let (lead, reason) = chooseLead(among: chosen, preferred: request.preferredLead, target: request.target)
        let period = PeriodDescriptor(candidates: chosen)
        let title = FactualTitleBuilder(calendar: library.calendar, locale: locale)
            .title(for: chosen, period: period, story: library.story, userTitle: request.userTitle)
        let sequence = MemorySequencePlanner().sequence(chosen, lead: lead)
        let distinct = request.mode == .automatic
            ? chosen + alternates
            : chosen
        let recommendations = CreationRecommender.recommendations(distinct: distinct, period: PeriodDescriptor(candidates: distinct))

        var limitations: [MemorySelectionPlan.Limitation] = []
        if !missing.isEmpty { limitations.append(.missing(missing.count)) }
        if !hidden.isEmpty { limitations.append(.hidden(hidden.count)) }
        if !notUsable.isEmpty { limitations.append(.notUsable(notUsable.count)) }
        let undated = chosen.filter { $0.captureDate == nil }.count
        if undated > 0 { limitations.append(.undated(undated)) }
        let unplaced = chosen.filter { $0.place == nil && !$0.hasLocation }.count
        if unplaced > 0 { limitations.append(.unplaced(unplaced)) }
        if repeated > 0 { limitations.append(.repeatedSimilar(repeated)) }

        let plan = MemorySelectionPlan(
            target: request.target,
            mode: request.mode,
            status: chosen.count >= minimum && !chosen.isEmpty ? .ready : .insufficient(available: chosen.count, required: max(1, minimum)),
            sourceCount: all.count,
            selected: chosen.map(\.assetID),
            lead: lead,
            leadReason: reason,
            alternates: Array(alternates.prefix(8).map(\.assetID)),
            excludedDuplicates: request.mode == .automatic ? duplicateList : [],
            collapsedSimilar: collapsed,
            similarityClusterCount: clusters.count,
            nearDuplicateSelections: nearDuplicateSelections,
            period: period,
            title: title,
            sequence: sequence,
            recommendations: recommendations,
            limitations: limitations
        )
        if logsDiagnostics { IntelligenceDiagnostics.emit(plan.diagnosticsLine) }
        return plan
    }

    // MARK: - Leads

    /// The best lead among `ids` for `target`: a user's cover, a favorite, a moment's cover,
    /// then image quality (and, for stories, a tall photo).
    public func lead(among ids: [AssetID], target: IntelligenceTarget) -> AssetID? {
        chooseLead(among: MemoryCandidate.build(ids, library: library).filter { $0.isAvailable && $0.isUsable }, preferred: nil, target: target).id
    }

    /// Each photo's place in the lead ranking (0 = best), for code that only needs an order —
    /// the suitability itself never leaves the engine.
    public func leadRanks(_ ids: [AssetID], target: IntelligenceTarget) -> [AssetID: Int] {
        Dictionary(rankedLeads(ids, target: target).enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    /// `ids` ranked as leads, best first (for "Make it for me" variations).
    public func rankedLeads(_ ids: [AssetID], target: IntelligenceTarget) -> [AssetID] {
        MemoryCandidate.build(ids, library: library)
            .sorted { ranker.ranksBefore($0, $1) { ranker.leadSuitability($0, for: target) } }
            .map(\.assetID)
    }

    private func chooseLead(among candidates: [MemoryCandidate], preferred: AssetID?, target: IntelligenceTarget) -> (id: AssetID?, reason: MemorySelectionPlan.LeadReason) {
        if let preferred, candidates.contains(where: { $0.assetID == preferred }) {
            return (preferred, .userChoice)
        }
        guard let best = candidates.min(by: { ranker.ranksBefore($0, $1) { ranker.leadSuitability($0, for: target) } }) else {
            return (nil, .none)
        }
        let reason: MemorySelectionPlan.LeadReason = best.isUserCover ? .userCover
            : best.isFavorite ? .favorite
            : best.isMomentCover ? .momentCover
            : .quality
        return (best.assetID, reason)
    }

    // MARK: - Look-alikes

    /// Two photos of the same scene taken further apart than a burst (and so not collapsed as
    /// near-identical): same day, close in look. Results are cached per pair.
    private func lookAlikeTest() -> (MemoryCandidate, MemoryCandidate) -> Bool {
        let cache = LookAlikeCache()
        let library = library
        let detector = detector
        return { lhs, rhs in
            guard lhs.day != nil, lhs.day == rhs.day,
                  let left = library.assets[lhs.assetID], let right = library.assets[rhs.assetID] else { return false }
            let key = lhs.assetID < rhs.assetID ? "\(lhs.assetID)|\(rhs.assetID)" : "\(rhs.assetID)|\(lhs.assetID)"
            if let known = cache.values[key] { return known }
            let result = detector.looksAlike(left, right)
            cache.values[key] = result
            return result
        }
    }

    // MARK: - Duplicates outside the story

    /// Photos picked from the photo library aren't in the story, so the engine never compared
    /// them. Each is checked against the others (cost: picks × candidates).
    private func outsideStoryDuplicates(_ candidates: [MemoryCandidate]) -> Set<AssetID> {
        let outside = candidates.filter { library.photoLibraryAssetIDs.contains($0.assetID) }
        guard !outside.isEmpty else { return [] }
        let assets = candidates.compactMap { library.assets[$0.assetID] }
        var copies = Set<AssetID>()
        for pick in outside {
            guard let asset = library.assets[pick.assetID] else { continue }
            for other in assets where other.id != asset.id && !copies.contains(other.id) {
                guard detector.isDuplicate(asset, other) else { continue }
                // Keep the better copy (Relive's own rule), drop the other.
                let worse = DuplicateDetector.primaryPreference(asset, other) ? asset.id : other.id
                copies.insert(worse)
            }
        }
        return copies
    }
}

/// DEBUG explainability. The app sets a sink in development builds; nothing is logged otherwise.
/// Per-plan memo of look-alike comparisons (a plan runs on one thread).
private final class LookAlikeCache: @unchecked Sendable {
    var values: [String: Bool] = [:]
}

public enum IntelligenceDiagnostics {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sink: (@Sendable (String) -> Void)?

    public static func setSink(_ newSink: (@Sendable (String) -> Void)?) {
        lock.withLock { sink = newSink }
    }

    public static func emit(_ line: String) {
        let current = lock.withLock { sink }
        current?(line)
    }
}

// MARK: - Codes for diagnostics

extension IntelligenceTarget {
    var code: String {
        switch self {
        case .collage: "collage"
        case .story: "story"
        case .book: "book"
        case .general(let limit): "general\(limit)"
        }
    }
}

extension PeriodDescriptor {
    /// "2026-08", "2026-08..2026-10", "2025-2026", "2026-06-08", "unknown".
    var code: String {
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        switch kind {
        case .day(let day): return "\(day.year)-\(two(day.month))-\(two(day.day))"
        case .days(let first, let last): return "\(first.year)-\(two(first.month))-\(two(first.day))..\(two(last.day))"
        case .month(let month): return "\(month.year)-\(two(month.month))"
        case .months(let first, let last): return "\(first.year)-\(two(first.month))..\(last.year)-\(two(last.month))"
        case .years(let first, let last): return "\(first)-\(last)"
        case .unknown: return "unknown"
        }
    }
}

extension MemorySelectionPlan.Limitation {
    var code: String {
        switch self {
        case .missing(let count): "missing:\(count)"
        case .hidden(let count): "hidden:\(count)"
        case .notUsable(let count): "notUsable:\(count)"
        case .undated(let count): "undated:\(count)"
        case .unplaced(let count): "unplaced:\(count)"
        case .repeatedSimilar(let count): "repeatedSimilar:\(count)"
        }
    }
}
