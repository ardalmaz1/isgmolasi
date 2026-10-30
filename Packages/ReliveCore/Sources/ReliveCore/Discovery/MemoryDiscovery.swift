import Foundation

// First Experience V2: on-device discovery of possible moments, confirmed by the user.
//
// With the user's explicit permission to look through the photo library, Relive proposes a
// short list of *possible* moments — groups of photos taken close together in time and place —
// and the user keeps the ones that belong in their story. Nothing is identified: Relive never
// knows who is in a photo. Face detection only counts faces, as one ranking signal among many.
//
//   library metadata (dates, places, favourites, kinds — no pixels)
//     → eligible assets (dated, after the relationship start when known, no screenshots)
//     → moments (`MomentClusterer`) and trips (`ChapterBuilder`) — the story engine's own rules
//     → metadata ranking → a bounded shortlist
//     → small local thumbnails of a few representatives per shortlisted moment
//       (face count, utility, aesthetics — the existing analyser)
//     → final ranking → at most `maximumCandidates` possible moments
//     → the user keeps or skips each one
//     → only kept moments' photos are imported and processed by the Memory Engine
//
// The amount of image work is bounded by `maximumCandidates × representativesPerCandidate`,
// whatever the size of the library. Everything here is a value computation: the photo library
// adapter and the analyser live in the app.
// See docs/FIRST_EXPERIENCE_V2.md.

/// The bounds of one discovery pass.
public struct DiscoveryConfiguration: Hashable, Sendable {
    /// Newest assets whose metadata is considered (very large libraries: the most recent ones).
    public var maximumLibraryAssets: Int
    /// Moments shortlisted by metadata before any image is looked at.
    public var shortlistSize: Int
    /// Possible moments shown to the user.
    public var maximumCandidates: Int
    /// Small thumbnails analysed per shortlisted moment.
    public var representativesPerCandidate: Int
    /// A possible moment needs at least this many photos or videos.
    public var minimumAssetsPerCandidate: Int
    /// No more than this many possible moments from one calendar year, so a long relationship
    /// isn't summarised by its most photographed year.
    public var maximumCandidatesPerYear: Int
    /// Photos smaller than this on their long side are skipped (stickers, saved thumbnails).
    public var minimumLongSide: Int
    /// The most photos the first story imports from the moments the user kept.
    public var maximumImportedAssets: Int

    public init(
        maximumLibraryAssets: Int = 25_000,
        shortlistSize: Int = 48,
        maximumCandidates: Int = 36,
        representativesPerCandidate: Int = 3,
        minimumAssetsPerCandidate: Int = 3,
        maximumCandidatesPerYear: Int = 12,
        minimumLongSide: Int = 320,
        maximumImportedAssets: Int = 1_000
    ) {
        self.maximumLibraryAssets = maximumLibraryAssets
        self.shortlistSize = shortlistSize
        self.maximumCandidates = maximumCandidates
        self.representativesPerCandidate = representativesPerCandidate
        self.minimumAssetsPerCandidate = minimumAssetsPerCandidate
        self.maximumCandidatesPerYear = maximumCandidatesPerYear
        self.minimumLongSide = minimumLongSide
        self.maximumImportedAssets = maximumImportedAssets
    }

    public static let standard = DiscoveryConfiguration()

    /// The most thumbnails one pass may analyse.
    public var maximumAnalysedThumbnails: Int { shortlistSize * representativesPerCandidate }
}

/// How many faces a representative photo has. A count only — never who.
public enum FaceSignal: String, Hashable, Sendable, Codable {
    /// No thumbnail was available on this iPhone (e.g. only in iCloud) or analysis failed.
    case unknown
    case none
    case one
    case twoOrMore

    public init(faceCount: Int?) {
        switch faceCount {
        case nil: self = .unknown
        case 0?: self = .none
        case 1?: self = .one
        default: self = .twoOrMore
        }
    }
}

/// What a representative's small local thumbnail showed. No face geometry, no identity.
public struct RepresentativeAnalysis: Hashable, Sendable {
    /// `nil` when no local thumbnail was available.
    public var faceCount: Int?
    public var isUtility: Bool
    /// 0...1, when known.
    public var aesthetic: Double?

    public init(faceCount: Int?, isUtility: Bool = false, aesthetic: Double? = nil) {
        self.faceCount = faceCount
        self.isUtility = isUtility
        self.aesthetic = aesthetic
    }

    /// No thumbnail on this iPhone.
    public static let unavailable = RepresentativeAnalysis(faceCount: nil)

    public var isAvailable: Bool { faceCount != nil }
}

/// A possible moment: a suggestion, never a claim that it belongs to the couple.
public struct DiscoveryCandidate: Identifiable, Hashable, Sendable {
    public var id: String
    /// Every photo and video in it, oldest first.
    public var assetIDs: [AssetID]
    /// The few photos whose thumbnails are analysed and shown.
    public var representativeIDs: [AssetID]
    public var start: Date
    public var end: Date
    public var photoCount: Int
    public var videoCount: Int
    public var favoriteCount: Int
    /// Several days away from the places most photos are taken.
    public var isTrip: Bool
    public var hasLocation: Bool
    /// Ranking from metadata alone.
    public var metadataScore: Double
    /// The strongest face signal among the representatives (a count, never an identity).
    public var faces: FaceSignal
    /// Representatives that had no local thumbnail.
    public var unavailableRepresentatives: Int
    /// The final ranking.
    public var score: Double

    public var assetCount: Int { assetIDs.count }

    /// Calendar days the moment spans.
    public func dayCount(calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        return max(1, days + 1)
    }
}

/// Counts only — safe for DEBUG diagnostics.
public struct DiscoveryDiagnostics: Hashable, Sendable {
    public var libraryAssets = 0
    public var considered = 0
    public var eligible = 0
    public var excludedUndated = 0
    public var excludedBeforeStart = 0
    public var excludedNoise = 0
    public var moments = 0
    public var trips = 0
    public var shortlisted = 0
    public var representatives = 0

    public init() {}

    public var line: String {
        "discovery_plan library=\(libraryAssets) considered=\(considered) eligible=\(eligible) undated=\(excludedUndated) beforeStart=\(excludedBeforeStart) noise=\(excludedNoise) moments=\(moments) trips=\(trips) shortlisted=\(shortlisted) representatives=\(representatives)"
    }
}

/// The metadata stage's result: a shortlist whose representatives are to be analysed.
public struct DiscoveryShortlist: Hashable, Sendable {
    public var candidates: [DiscoveryCandidate]
    public var diagnostics: DiscoveryDiagnostics

    /// Every thumbnail the image stage may look at (bounded by the configuration).
    public var representativeIDs: [AssetID] { candidates.flatMap(\.representativeIDs) }
}

/// Finds possible moments in library metadata, then ranks them with a few thumbnail signals.
public struct MemoryDiscovery: Sendable {
    public var configuration: DiscoveryConfiguration
    public var calendar: Calendar
    public var clustering: ClusteringConfiguration
    public var chapters: ChapterConfiguration

    public init(
        configuration: DiscoveryConfiguration = .standard,
        calendar: Calendar,
        clustering: ClusteringConfiguration = .standard,
        chapters: ChapterConfiguration = .standard
    ) {
        self.configuration = configuration
        self.calendar = calendar
        self.clustering = clustering
        self.chapters = chapters
    }

    // MARK: - Metadata stage

    /// Groups library metadata into possible moments and shortlists the strongest. No images.
    ///
    /// - Parameters:
    ///   - library: the library's photos and videos (metadata only), in any order.
    ///   - relationshipStart: when known, only memories from that day on are suggested.
    public func shortlist(from library: [MemoryAsset], relationshipStart: Date?, now: Date) -> DiscoveryShortlist {
        var diagnostics = DiscoveryDiagnostics()
        diagnostics.libraryAssets = library.count

        // Very large libraries: the most recent assets (a newest-first fetch is cheap).
        let considered = library
            .filter { $0.creationDate != nil }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            .prefix(configuration.maximumLibraryAssets)
        diagnostics.excludedUndated = library.count - library.filter { $0.creationDate != nil }.count
        diagnostics.considered = considered.count

        let startDay = relationshipStart.map { calendar.startOfDay(for: $0) }
        let latest = now.addingTimeInterval(86_400)
        var eligible: [MemoryAsset] = []
        for asset in considered {
            guard let date = asset.creationDate, date <= latest else {
                diagnostics.excludedNoise += 1
                continue
            }
            if let startDay, date < startDay {
                diagnostics.excludedBeforeStart += 1
                continue
            }
            if isNoise(asset) {
                diagnostics.excludedNoise += 1
                continue
            }
            eligible.append(asset)
        }
        diagnostics.eligible = eligible.count

        // The story engine's own moment and trip rules.
        let clusters = MomentClusterer(configuration: clustering, calendar: calendar).cluster(eligible)
        diagnostics.moments = clusters.count
        let summaries = clusters.map { cluster -> ClusterSummary in
            ClusterSummary(
                start: cluster.first?.creationDate ?? now,
                end: cluster.last?.creationDate ?? now,
                centroid: GeoCoordinate.centroid(of: cluster.compactMap(\.location))
            )
        }
        let runs = ChapterBuilder(configuration: chapters, calendar: calendar).chapterRuns(for: summaries)
        diagnostics.trips = runs.count

        var groups: [(assets: [MemoryAsset], isTrip: Bool)] = []
        var inTrip = Set<Int>()
        for run in runs {
            inTrip.formUnion(run)
            groups.append((run.flatMap { clusters[$0] }, true))
        }
        for (index, cluster) in clusters.enumerated() where !inTrip.contains(index) {
            groups.append((cluster, false))
        }

        let candidates = groups
            .filter { $0.assets.count >= configuration.minimumAssetsPerCandidate }
            .map { makeCandidate($0.assets, isTrip: $0.isTrip) }
        let shortlisted = Self.select(
            candidates.sorted(by: Self.ranked),
            limit: configuration.shortlistSize,
            perYear: configuration.maximumCandidatesPerYear,
            calendar: calendar
        )
        diagnostics.shortlisted = shortlisted.count
        diagnostics.representatives = shortlisted.reduce(0) { $0 + $1.representativeIDs.count }
        return DiscoveryShortlist(candidates: shortlisted, diagnostics: diagnostics)
    }

    /// Screenshots and tiny images aren't memories. (Hidden assets and shared-album items are left
    /// out by the photo library adapter.)
    func isNoise(_ asset: MemoryAsset) -> Bool {
        if asset.isScreenshot { return true }
        let longSide = max(asset.pixelWidth, asset.pixelHeight)
        return longSide > 0 && longSide < configuration.minimumLongSide
    }

    func makeCandidate(_ assets: [MemoryAsset], isTrip: Bool) -> DiscoveryCandidate {
        let sorted = assets.sorted(by: MetadataProcessor.chronological)
        let start = sorted.first?.creationDate ?? .distantPast
        let end = sorted.last?.creationDate ?? start
        let photos = sorted.filter { $0.kind == .photo }
        let favorites = sorted.filter(\.isFavorite).count
        let hasLocation = sorted.contains { $0.location != nil }
        var candidate = DiscoveryCandidate(
            id: "candidate:\(sorted.first?.id ?? UUID().uuidString)",
            assetIDs: sorted.map(\.id),
            representativeIDs: Self.representatives(of: sorted, count: configuration.representativesPerCandidate),
            start: start,
            end: end,
            photoCount: photos.count,
            videoCount: sorted.count - photos.count,
            favoriteCount: favorites,
            isTrip: isTrip,
            hasLocation: hasLocation,
            metadataScore: 0,
            faces: .unknown,
            unavailableRepresentatives: 0,
            score: 0
        )
        candidate.metadataScore = metadataScore(candidate)
        candidate.score = candidate.metadataScore
        return candidate
    }

    /// Ranking from metadata only: size (diminishing), trips, days, favourites, places, videos.
    func metadataScore(_ candidate: DiscoveryCandidate) -> Double {
        var score = log2(Double(max(1, candidate.assetCount)))
        if candidate.isTrip { score += 2.5 }
        score += min(1.5, Double(candidate.dayCount(calendar: calendar) - 1) * 0.5)
        score += min(2, Double(candidate.favoriteCount) * 0.5)
        if candidate.hasLocation { score += 0.3 }
        if candidate.videoCount > 0 { score += 0.2 }
        return score
    }

    /// Up to `count` photos spread across the moment: favourites first, then evenly in time.
    static func representatives(of assets: [MemoryAsset], count: Int) -> [AssetID] {
        let photos = assets.filter { $0.kind == .photo }
        let pool = photos.isEmpty ? assets : photos
        guard pool.count > count else { return pool.map(\.id) }
        var chosen: [AssetID] = []
        for favorite in pool where favorite.isFavorite && chosen.count < count {
            chosen.append(favorite.id)
        }
        var step = 0
        while chosen.count < count, step < pool.count {
            let index = count <= 1 ? pool.count / 2 : Int((Double(step) / Double(max(1, count - 1))) * Double(pool.count - 1))
            let id = pool[min(pool.count - 1, index)].id
            if !chosen.contains(id) { chosen.append(id) }
            step += 1
        }
        var fill = 0
        while chosen.count < count, fill < pool.count {
            if !chosen.contains(pool[fill].id) { chosen.append(pool[fill].id) }
            fill += 1
        }
        return chosen
    }

    // MARK: - Image stage

    /// Re-ranks the shortlist with the representatives' thumbnail signals and returns the
    /// possible moments to show, newest first.
    ///
    /// Signals (face counts — never who): photos with one or two faces raise a moment, group
    /// photos (three or more) lower it, and a moment made mostly of group photos with none of
    /// one or two people is dropped — it is more likely friends than the couple. A moment whose
    /// analysed representatives are mostly utility images (documents, notes, receipts) is
    /// dropped; aesthetics nudge. A moment without local thumbnails keeps its metadata ranking.
    public func refine(_ shortlist: DiscoveryShortlist, analyses: [AssetID: RepresentativeAnalysis]) -> [DiscoveryCandidate] {
        var refined: [DiscoveryCandidate] = []
        for var candidate in shortlist.candidates {
            let results = candidate.representativeIDs.map { analyses[$0] ?? .unavailable }
            let available = results.filter(\.isAvailable)
            candidate.unavailableRepresentatives = results.count - available.count
            candidate.faces = available.map { FaceSignal(faceCount: $0.faceCount) }.max(by: Self.weaker) ?? .unknown
            let utilityShare = Self.share(of: available) { $0.isUtility }
            if !available.isEmpty, utilityShare >= 0.5 { continue }
            let pairShare = Self.share(of: available) { (1...2).contains($0.faceCount ?? 0) }
            let groupShare = Self.share(of: available) { ($0.faceCount ?? 0) >= 3 }
            if available.count >= 2, groupShare >= 0.5, pairShare == 0 { continue }

            var score = candidate.metadataScore
            score += pairShare * 2.5 - groupShare * 1.5
            if candidate.faces == .none { score -= 0.5 }
            let aesthetics = available.compactMap(\.aesthetic)
            if !aesthetics.isEmpty {
                score += (aesthetics.reduce(0, +) / Double(aesthetics.count) - 0.5)
            }
            score -= utilityShare
            candidate.score = score
            refined.append(candidate)
        }
        let chosen = Self.select(
            refined.sorted(by: Self.ranked),
            limit: configuration.maximumCandidates,
            perYear: configuration.maximumCandidatesPerYear,
            calendar: calendar
        )
        return chosen.sorted { $0.start > $1.start }
    }

    // MARK: - After confirmation

    /// The photos to import from the moments the user kept: all of them, unless that exceeds
    /// `maximumImportedAssets`, in which case each kept moment contributes in proportion to its
    /// size, spread evenly across its time (never zero from a kept moment). Nothing from a
    /// moment the user didn't keep is ever included.
    public func importIdentifiers(for kept: [DiscoveryCandidate]) -> [AssetID] {
        let total = kept.reduce(0) { $0 + $1.assetCount }
        guard total > configuration.maximumImportedAssets else {
            return kept.flatMap(\.assetIDs)
        }
        let ratio = Double(configuration.maximumImportedAssets) / Double(total)
        var result: [AssetID] = []
        for candidate in kept {
            let share = max(1, Int((Double(candidate.assetCount) * ratio).rounded(.down)))
            result += Self.evenlySpread(candidate.assetIDs, count: share)
        }
        return Array(result.prefix(configuration.maximumImportedAssets))
    }

    static func evenlySpread(_ ids: [AssetID], count: Int) -> [AssetID] {
        guard count < ids.count else { return ids }
        guard count > 0 else { return [] }
        if count == 1 { return [ids[ids.count / 2]] }
        return (0..<count).map { step in ids[Int((Double(step) / Double(count - 1)) * Double(ids.count - 1))] }
    }

    // MARK: - Ordering

    static func ranked(_ lhs: DiscoveryCandidate, _ rhs: DiscoveryCandidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.start != rhs.start { return lhs.start > rhs.start }
        return lhs.id < rhs.id
    }

    /// The share of `analyses` matching `predicate`; 0 when there are none.
    static func share(of analyses: [RepresentativeAnalysis], where predicate: (RepresentativeAnalysis) -> Bool) -> Double {
        analyses.isEmpty ? 0 : Double(analyses.filter(predicate).count) / Double(analyses.count)
    }

    static func weaker(_ lhs: FaceSignal, _ rhs: FaceSignal) -> Bool {
        let order: [FaceSignal] = [.unknown, .none, .one, .twoOrMore]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    /// The best `limit`, at most `perYear` from any one year.
    static func select(_ ranked: [DiscoveryCandidate], limit: Int, perYear: Int, calendar: Calendar) -> [DiscoveryCandidate] {
        var perYearCount: [Int: Int] = [:]
        var result: [DiscoveryCandidate] = []
        for candidate in ranked where result.count < limit {
            let year = calendar.component(.year, from: candidate.start)
            guard perYearCount[year, default: 0] < perYear else { continue }
            perYearCount[year, default: 0] += 1
            result.append(candidate)
        }
        return result
    }
}
