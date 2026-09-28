import Foundation

/// Turns selected assets into a Story.
///
/// ```
/// Selected assets
///   → Metadata processing        (MetadataProcessor)
///   → Image analysis             (AssetAnalyzing — Vision on device)
///   → Duplicate detection        (DuplicateDetector.duplicateGroups)
///   → Temporal + location moments (MomentClusterer)
///   → Trips                      (ChapterBuilder)
///   → Gathering small moments    (MomentConsolidator)
///   → Similar-shot collapsing    (DuplicateDetector.similarGroups)
///   → Place names                (PlaceNameResolving — reverse geocoding on device)
///   → Hero selection             (HeroSelector)
///   → Naming                     (MomentNamingService)
///   → Story
/// ```
///
/// Each stage is a small value type with its own configuration and tests, so any of them can be
/// improved or replaced independently. The engine itself holds no state; it can run on any
/// executor and honours task cancellation.
public struct MemoryEngine: Sendable {
    public var configuration: MemoryEngineConfiguration
    private let analyzer: any AssetAnalyzing
    private let placeResolver: any PlaceNameResolving
    private let namingService: any MomentNamingService

    public init(
        configuration: MemoryEngineConfiguration,
        analyzer: any AssetAnalyzing,
        placeResolver: any PlaceNameResolving,
        namingService: any MomentNamingService
    ) {
        self.configuration = configuration
        self.analyzer = analyzer
        self.placeResolver = placeResolver
        self.namingService = namingService
    }

    public func buildStory(
        from input: [MemoryAsset],
        now: Date = Date(),
        progress: @Sendable (MemoryEngineProgress) -> Void = { _ in }
    ) async throws -> MemoryEngineResult {
        var diagnostics = MemoryEngineDiagnostics()
        diagnostics.inputCount = input.count

        // 1. Metadata
        progress(MemoryEngineProgress(stage: .readingMetadata))
        let normalized = MetadataProcessor(futureTolerance: configuration.futureDateTolerance).process(input, now: now)
        diagnostics.undatedCount = normalized.undated.count

        // 2. Image analysis (cached results are reused)
        let analyzed = try await analyze(normalized.dated + normalized.undated, progress: progress)
        diagnostics.analyzedCount = analyzed.filter { $0.analysis != nil }.count
        diagnostics.analysisFailureCount = analyzed.filter {
            $0.analysis?.failures.contains(.thumbnailUnavailable) ?? true
        }.count
        diagnostics.locatedCount = analyzed.filter { $0.location != nil }.count
        let datedCount = normalized.dated.count
        let dated = Array(analyzed.prefix(datedCount))
        let undated = Array(analyzed.dropFirst(datedCount))

        // 3–6. Grouping
        progress(MemoryEngineProgress(stage: .findingMoments))
        try Task.checkCancellation()
        let grouping = group(dated: dated, undated: undated, all: analyzed)
        diagnostics.duplicateCount = grouping.duplicateCount
        diagnostics.similarCount = grouping.drafts.reduce(0) { $0 + $1.similar.count } - grouping.duplicateCount

        // 7. Places
        let places = try await resolvePlaces(for: grouping, progress: progress)
        diagnostics.namedPlaceCount = Set(places.values.map(\.comparisonKey)).count

        // 8–9. Heroes and names
        progress(MemoryEngineProgress(stage: .choosingFavorites))
        try Task.checkCancellation()
        let story = await assembleStory(grouping: grouping, places: places, now: now)
        diagnostics.momentCount = story.moments.count
        diagnostics.chapterCount = story.chapters.count

        progress(MemoryEngineProgress(stage: .finished, completedUnits: 1, totalUnits: 1))
        return MemoryEngineResult(
            story: story,
            assets: analyzed,
            diagnostics: diagnostics,
            duplicateGroups: grouping.duplicateGroups
        )
    }

    // MARK: - Analysis

    private func analyze(
        _ assets: [MemoryAsset],
        progress: @Sendable (MemoryEngineProgress) -> Void
    ) async throws -> [MemoryAsset] {
        var result = assets
        let pending = assets.indices.filter { !(assets[$0].analysis?.isCurrent ?? false) }
        progress(MemoryEngineProgress(stage: .analyzingImages, completedUnits: 0, totalUnits: pending.count))
        guard !pending.isEmpty else { return result }

        let analyzer = self.analyzer
        let width = max(1, configuration.analysisConcurrency)
        let priority = configuration.analysisPriority
        try await withThrowingTaskGroup(of: (Int, AssetAnalysis).self) { group in
            var nextPending = 0
            while nextPending < min(width, pending.count) {
                let index = pending[nextPending]
                let asset = assets[index]
                group.addTask(priority: priority) { (index, await analyzer.analyze(asset)) }
                nextPending += 1
            }

            var completed = 0
            while let finished = try await group.next() {
                result[finished.0].analysis = finished.1
                completed += 1
                progress(MemoryEngineProgress(stage: .analyzingImages, completedUnits: completed, totalUnits: pending.count))
                try Task.checkCancellation()

                if nextPending < pending.count {
                    let index = pending[nextPending]
                    let asset = assets[index]
                    group.addTask(priority: priority) { (index, await analyzer.analyze(asset)) }
                    nextPending += 1
                }
            }
        }
        return result
    }

    // MARK: - Grouping

    /// A moment before places, heroes and names are known.
    struct MomentDraft {
        var id: MomentID
        var kind: Moment.Kind
        /// Primaries (non-duplicate members), chronological.
        var members: [MemoryAsset]
        var featured: [AssetID]
        /// Collapsed similar shots and duplicate copies.
        var similar: [AssetID]
        var duplicates: [AssetID]
        var copies: [MemoryAsset]
        var similarShotCounts: [AssetID: Int]
        var centroid: GeoCoordinate?
        var chapterRun: Int?
        var isAtHome: Bool
        var start: Date?
        var end: Date?
    }

    struct ChapterDraft {
        var id: UUID
        var momentIndices: [Int]
        var start: Date
        var end: Date
        var centroid: GeoCoordinate?
    }

    struct Grouping {
        var drafts: [MomentDraft]
        var chapters: [ChapterDraft]
        var duplicateCount: Int
        var duplicateGroups: [DuplicateDetector.DuplicateGroup]
    }

    private func group(dated: [MemoryAsset], undated: [MemoryAsset], all: [MemoryAsset]) -> Grouping {
        let calendar = configuration.calendar
        let detector = DuplicateDetector(configuration: configuration.similarity)
        let scorer = AssetScorer(weights: configuration.heroWeights)

        // Duplicates: copies leave clustering and are re-attached to their original's moment.
        let duplicateGroups = detector.duplicateGroups(in: all)
        var primaryOfCopy: [AssetID: AssetID] = [:]
        for group in duplicateGroups {
            for copy in group.copies { primaryOfCopy[copy] = group.primary }
        }
        let datedPrimaries = dated.filter { primaryOfCopy[$0.id] == nil }
        let undatedPrimaries = undated.filter { primaryOfCopy[$0.id] == nil }

        // Moments by time and place.
        let clusters = MomentClusterer(configuration: configuration.clustering, calendar: calendar).cluster(datedPrimaries)
        let summaries = clusters.map { cluster in
            ClusterSummary(
                start: cluster.first?.creationDate ?? .distantPast,
                end: cluster.last?.creationDate ?? .distantPast,
                centroid: coherentLocation(of: cluster)
            )
        }

        // Trips, and which moments are everyday life at home.
        let chapterBuilder = ChapterBuilder(configuration: configuration.chapters, calendar: calendar)
        let runs = chapterBuilder.chapterRuns(for: summaries)
        let homeFlags = chapterBuilder.homeFlags(for: summaries)
        var runOfCluster: [Int: Int] = [:]
        for (runIndex, run) in runs.enumerated() {
            for clusterIndex in run { runOfCluster[clusterIndex] = runIndex }
        }

        // Small moments gathered by month (never inside a trip).
        let groups = MomentConsolidator(configuration: configuration.consolidation, calendar: calendar).consolidate(
            sizes: clusters.map(\.count),
            startDates: summaries.map(\.start),
            protectedIndices: Set(runOfCluster.keys)
        )

        var drafts: [MomentDraft] = []
        for group in groups {
            let members = group.clusterIndices.flatMap { clusters[$0] }.sorted(by: MetadataProcessor.chronological)
            let kind: Moment.Kind = group.isCollection ? .collection : .event
            let run = group.isCollection ? nil : group.clusterIndices.first.flatMap { runOfCluster[$0] }
            let atHome = group.clusterIndices.allSatisfy { homeFlags[$0] }
            drafts.append(makeDraft(kind: kind, members: members, chapterRun: run, isAtHome: atHome))
        }
        if !undatedPrimaries.isEmpty {
            drafts.append(makeDraft(kind: .undated, members: undatedPrimaries, chapterRun: nil, isAtHome: false))
        }

        // Attach copies to the moment of their original.
        let assetsByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var draftOfAsset: [AssetID: Int] = [:]
        for (index, draft) in drafts.enumerated() {
            for member in draft.members { draftOfAsset[member.id] = index }
        }
        for (copy, primary) in primaryOfCopy.sorted(by: { $0.key < $1.key }) {
            guard let draftIndex = draftOfAsset[primary], let asset = assetsByID[copy] else { continue }
            drafts[draftIndex].copies.append(asset)
        }

        // Collapse near-identical shots inside each moment.
        for index in drafts.indices {
            collapseSimilar(in: &drafts[index], detector: detector, scorer: scorer)
        }

        // Chapters from runs.
        var chapters: [ChapterDraft] = []
        for runIndex in runs.indices {
            let momentIndices = drafts.indices.filter { drafts[$0].chapterRun == runIndex }
            guard let first = momentIndices.first, let firstMember = drafts[first].members.first else { continue }
            let starts = momentIndices.compactMap { drafts[$0].start }
            let ends = momentIndices.compactMap { drafts[$0].end }
            guard let start = starts.min(), let end = ends.max() else { continue }
            chapters.append(ChapterDraft(
                id: StableIdentifier.uuid(namespace: "chapter", key: firstMember.id),
                momentIndices: momentIndices,
                start: start,
                end: end,
                centroid: GeoCoordinate.centroid(of: momentIndices.compactMap { drafts[$0].centroid })
            ))
        }

        return Grouping(
            drafts: drafts,
            chapters: chapters,
            duplicateCount: primaryOfCopy.count,
            duplicateGroups: duplicateGroups
        )
    }

    private func makeDraft(kind: Moment.Kind, members: [MemoryAsset], chapterRun: Int?, isAtHome: Bool) -> MomentDraft {
        let dates = members.compactMap(\.creationDate)
        let key = members.first?.id ?? UUID().uuidString
        let centroid: GeoCoordinate?
        switch kind {
        case .event: centroid = coherentLocation(of: members)
        case .collection: centroid = strictlyCoherentCentroid(of: members)
        case .undated: centroid = nil
        }
        return MomentDraft(
            id: StableIdentifier.uuid(namespace: kind.rawValue, key: key),
            kind: kind,
            members: members,
            featured: members.map(\.id),
            similar: [],
            duplicates: [],
            copies: [],
            similarShotCounts: [:],
            centroid: centroid,
            chapterRun: chapterRun,
            isAtHome: isAtHome,
            start: dates.min(),
            end: dates.max()
        )
    }

    private func collapseSimilar(in draft: inout MomentDraft, detector: DuplicateDetector, scorer: AssetScorer) {
        let groups = detector.similarGroups(in: draft.members) { scorer.score($0) }
        var collapsed = Set<AssetID>()
        var counts: [AssetID: Int] = [:]
        let favorites = Set(draft.members.filter(\.isFavorite).map(\.id))
        for group in groups {
            let hidden = group.members.filter { $0 != group.representative && !favorites.contains($0) }
            collapsed.formUnion(hidden)
            counts[group.representative] = hidden.count
        }
        draft.featured = draft.members.map(\.id).filter { !collapsed.contains($0) }
        let copies = draft.copies.sorted(by: MetadataProcessor.chronological).map(\.id)
        draft.similar = draft.members.map(\.id).filter { collapsed.contains($0) } + copies
        draft.duplicates = copies
        draft.similarShotCounts = counts
    }

    /// Where a moment happened. If its located photos are close together, their centre; if they
    /// are spread out (a road trip day), the location with the most photos nearby.
    private func coherentLocation(of assets: [MemoryAsset]) -> GeoCoordinate? {
        let locations = assets.compactMap(\.location)
        guard let centroid = GeoCoordinate.centroid(of: locations) else { return nil }
        let spread = locations.map { $0.distance(to: centroid) }.max() ?? 0
        if spread <= configuration.coherentPlaceRadius { return centroid }
        return locations.max { lhs, rhs in
            let left = locations.filter { $0.distance(to: lhs) <= 5_000 }.count
            let right = locations.filter { $0.distance(to: rhs) <= 5_000 }.count
            return left < right
        }
    }

    /// Collections span many days; only name them after a place if all of it happened there.
    private func strictlyCoherentCentroid(of assets: [MemoryAsset]) -> GeoCoordinate? {
        let locations = assets.compactMap(\.location)
        guard locations.count == assets.count, let centroid = GeoCoordinate.centroid(of: locations) else { return nil }
        let spread = locations.map { $0.distance(to: centroid) }.max() ?? 0
        return spread <= configuration.coherentPlaceRadius ? centroid : nil
    }

    // MARK: - Places

    private func resolvePlaces(
        for grouping: Grouping,
        progress: @Sendable (MemoryEngineProgress) -> Void
    ) async throws -> [String: PlaceName] {
        var unique: [String: GeoCoordinate] = [:]
        var order: [String] = []
        for coordinate in grouping.drafts.compactMap(\.centroid) + grouping.chapters.compactMap(\.centroid) {
            let key = coordinate.placeLookupKey
            if unique[key] == nil {
                unique[key] = coordinate
                order.append(key)
            }
        }

        progress(MemoryEngineProgress(stage: .findingPlaces, completedUnits: 0, totalUnits: order.count))
        var names: [String: PlaceName] = [:]
        for (index, key) in order.enumerated() {
            try Task.checkCancellation()
            if let coordinate = unique[key], let name = await placeResolver.placeName(for: coordinate) {
                names[key] = name
            }
            progress(MemoryEngineProgress(stage: .findingPlaces, completedUnits: index + 1, totalUnits: order.count))
        }
        return names
    }

    // MARK: - Assembly

    private func assembleStory(grouping: Grouping, places: [String: PlaceName], now: Date) async -> Story {
        let heroSelector = HeroSelector(scorer: AssetScorer(weights: configuration.heroWeights))
        let drafts = grouping.drafts

        func place(for coordinate: GeoCoordinate?) -> PlaceName? {
            coordinate.flatMap { places[$0.placeLookupKey] }
        }

        // Chapters first: moment names depend on the chapter's place.
        var chapterIDOfMoment: [Int: UUID] = [:]
        var chapterPlaceOfMoment: [Int: PlaceName] = [:]
        var chapters: [Chapter] = []
        for draft in grouping.chapters {
            let momentPlaces = draft.momentIndices.compactMap { place(for: drafts[$0].centroid) }
            let chapterPlace = MemoryEngine.mostFrequent(momentPlaces) ?? place(for: draft.centroid)
            let title = await namingService.title(forChapter: ChapterNamingContext(
                start: draft.start,
                end: draft.end,
                place: chapterPlace,
                momentCount: draft.momentIndices.count
            ))
            chapters.append(Chapter(
                id: draft.id,
                momentIDs: draft.momentIndices.map { drafts[$0].id },
                startDate: draft.start,
                endDate: draft.end,
                centroid: draft.centroid,
                place: chapterPlace,
                title: title
            ))
            for momentIndex in draft.momentIndices {
                chapterIDOfMoment[momentIndex] = draft.id
                if let chapterPlace { chapterPlaceOfMoment[momentIndex] = chapterPlace }
            }
        }

        var moments: [Moment] = []
        for (index, draft) in drafts.enumerated() {
            let featuredAssets = draft.members.filter { draft.featured.contains($0.id) }
            let hero = heroSelector.selectHero(among: featuredAssets, similarShotCounts: draft.similarShotCounts)
            let momentPlace = place(for: draft.centroid)
            let title = await namingService.title(for: MomentNamingContext(
                kind: draft.kind,
                start: draft.start,
                end: draft.end,
                place: momentPlace,
                chapterPlace: chapterPlaceOfMoment[index],
                isInChapter: chapterIDOfMoment[index] != nil,
                isAtHome: draft.isAtHome,
                assetCount: draft.members.count
            ))
            let allAssets = (draft.members + draft.copies).sorted(by: MetadataProcessor.chronological)
            moments.append(Moment(
                id: draft.id,
                kind: draft.kind,
                assetIDs: allAssets.map(\.id),
                featuredAssetIDs: draft.featured,
                similarAssetIDs: draft.similar,
                duplicateAssetIDs: draft.duplicates,
                heroAssetID: hero,
                startDate: draft.start,
                endDate: draft.end,
                centroid: draft.centroid,
                place: momentPlace,
                title: title,
                chapterID: chapterIDOfMoment[index]
            ))
        }

        moments.sort { lhs, rhs in
            lhs.sortDate == rhs.sortDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortDate < rhs.sortDate
        }
        chapters.sort { $0.startDate < $1.startDate }
        return Story(generatedAt: now, moments: moments, chapters: chapters)
    }

    /// Most common place by comparison key; ties go to the first seen.
    static func mostFrequent(_ places: [PlaceName]) -> PlaceName? {
        var counts: [String: Int] = [:]
        for place in places { counts[place.comparisonKey, default: 0] += 1 }
        var best: PlaceName?
        var bestCount = 0
        for place in places {
            let count = counts[place.comparisonKey] ?? 0
            if count > bestCount {
                best = place
                bestCount = count
            }
        }
        return best
    }
}
