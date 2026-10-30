import Foundation
import Testing
@testable import ReliveCore

/// First Experience V2 fixtures: synthetic library metadata (no pixels), as the PhotoKit adapter
/// would hand it over.
enum DiscoveryFixture {
    static let now = date(2026, 10, 14, 12)
    static let home = GeoCoordinate(latitude: 41.04, longitude: 29.00)
    static let kas = GeoCoordinate(latitude: 36.20, longitude: 29.64)

    static func asset(_ id: String, _ when: Date?, location: GeoCoordinate? = nil, favorite: Bool = false, screenshot: Bool = false, longSide: Int = 4032, kind: MediaKind = .photo) -> MemoryAsset {
        MemoryAsset(
            localIdentifier: id,
            creationDate: when,
            location: location,
            kind: kind,
            traits: screenshot ? [.screenshot] : [],
            pixelWidth: longSide,
            pixelHeight: longSide * 3 / 4,
            isFavorite: favorite
        )
    }

    /// `count` photos from `start`, `spacing` seconds apart.
    static func burst(_ prefix: String, _ count: Int, start: Date, spacing: TimeInterval = 600, location: GeoCoordinate? = nil, favorite: Bool = false) -> [MemoryAsset] {
        (0..<count).map { asset("\(prefix)-\($0)", start.addingTimeInterval(Double($0) * spacing), location: location, favorite: favorite && $0 == 0) }
    }

    /// Everyday life at home across many months, a four-day trip to Kaş, and some noise.
    static func library() -> [MemoryAsset] {
        var assets: [MemoryAsset] = []
        for month in 1...9 {
            assets += burst("home-\(month)a", 4, start: date(2026, month, 3, 19), location: home)
            assets += burst("home-\(month)b", 3, start: date(2026, month, 17, 13), location: home)
        }
        for day in 6...9 {
            assets += burst("kas-\(day)", 8, start: date(2026, 8, day, 10), spacing: 1_800, location: kas, favorite: day == 7)
        }
        assets.append(asset("shot-1", date(2026, 8, 10, 9), screenshot: true))
        assets.append(asset("tiny-1", date(2026, 8, 10, 9, 5), longSide: 120))
        assets.append(asset("undated-1", nil))
        return assets
    }
}

@Suite("Discovery: possible moments from metadata")
struct DiscoveryShortlistTests {
    typealias F = DiscoveryFixture

    let discovery = MemoryDiscovery(calendar: testCalendar)

    @Test func aTripBecomesOnePossibleMomentAndLeads() throws {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let trip = try #require(shortlist.candidates.first { $0.isTrip })
        #expect(trip.assetCount == 32)
        #expect(trip.dayCount(calendar: testCalendar) == 4)
        #expect(trip.favoriteCount == 1)
        #expect(shortlist.candidates.first?.id == trip.id, "a trip ranks first on metadata alone")
        #expect(shortlist.diagnostics.trips == 1)
    }

    @Test func noiseUndatedAndScreenshotsAreLeftOut() {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let all = Set(shortlist.candidates.flatMap(\.assetIDs))
        #expect(!all.contains("shot-1"))
        #expect(!all.contains("tiny-1"))
        #expect(!all.contains("undated-1"))
        #expect(shortlist.diagnostics.excludedUndated == 1)
        #expect(shortlist.diagnostics.excludedNoise == 2)
    }

    @Test func theRelationshipStartLimitsWhatIsSuggested() {
        let start = date(2026, 6, 1)
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: start, now: F.now)
        #expect(shortlist.candidates.allSatisfy { $0.start >= testCalendar.startOfDay(for: start) })
        #expect(shortlist.diagnostics.excludedBeforeStart == 5 * 7)
        // Unknown start: everything dated is a possibility.
        let open = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        #expect(open.candidates.contains { $0.start < start })
    }

    @Test func representativesAreFewAndSpread() {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        for candidate in shortlist.candidates {
            #expect(candidate.representativeIDs.count <= 3)
            #expect(Set(candidate.representativeIDs).isSubset(of: Set(candidate.assetIDs)))
            #expect(Set(candidate.representativeIDs).count == candidate.representativeIDs.count)
        }
        let trip = shortlist.candidates.first { $0.isTrip }
        #expect(trip?.representativeIDs.first == "kas-7-0", "a favourite represents the moment first")
    }

    @Test func aHugeLibraryStaysBounded() {
        // 50,000 assets over ten years: metadata work only, a bounded shortlist.
        var assets: [MemoryAsset] = []
        assets.reserveCapacity(50_000)
        // Five photos an evening, every evening, for about 27 years.
        let start = date(1999, 6, 1, 19)
        for index in 0..<50_000 {
            let day = Double(index / 5) * 86_400
            let when = start.addingTimeInterval(day + Double(index % 5) * 600)
            assets.append(F.asset("big-\(index)", when, location: (index / 5) % 3 == 0 ? F.home : nil))
        }
        let clock = ContinuousClock()
        var shortlist = DiscoveryShortlist(candidates: [], diagnostics: DiscoveryDiagnostics())
        let elapsed = clock.measure {
            shortlist = discovery.shortlist(from: assets, relationshipStart: nil, now: F.now)
        }
        print("DISCOVERY_PERF linux assets=50000 considered=\(shortlist.diagnostics.considered) moments=\(shortlist.diagnostics.moments) shortlisted=\(shortlist.candidates.count) representatives=\(shortlist.representativeIDs.count) elapsed=\(elapsed)")
        #expect(shortlist.diagnostics.considered == DiscoveryConfiguration.standard.maximumLibraryAssets)
        #expect(shortlist.diagnostics.moments > 1_000, "the newest 25,000 still form thousands of moments")
        #expect(shortlist.candidates.count == DiscoveryConfiguration.standard.shortlistSize)
        #expect(shortlist.candidates.count <= DiscoveryConfiguration.standard.shortlistSize)
        #expect(shortlist.representativeIDs.count <= DiscoveryConfiguration.standard.maximumAnalysedThumbnails)
        let years = Dictionary(grouping: shortlist.candidates) { testCalendar.component(.year, from: $0.start) }
        #expect(years.values.allSatisfy { $0.count <= DiscoveryConfiguration.standard.maximumCandidatesPerYear })
        #expect(elapsed < .seconds(30), "\(elapsed)")
    }
}

@Suite("Discovery: thumbnail signals and confirmation")
struct DiscoveryRefineTests {
    typealias F = DiscoveryFixture

    let discovery = MemoryDiscovery(calendar: testCalendar)

    @Test func twoOrMoreFacesRaiseAMomentAsACountOnly() throws {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let home = try #require(shortlist.candidates.first { !$0.isTrip })
        var analyses: [AssetID: RepresentativeAnalysis] = [:]
        for id in shortlist.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 0, aesthetic: 0.5) }
        for id in home.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 2, aesthetic: 0.5) }
        let refined = discovery.refine(shortlist, analyses: analyses)
        let raised = try #require(refined.first { $0.id == home.id })
        #expect(raised.faces == .twoOrMore)
        #expect(raised.score > home.metadataScore)
    }

    @Test func utilityOnlyMomentsAreDroppedAndUnavailableThumbnailsAreNeutral() throws {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let first = try #require(shortlist.candidates.first)
        let second = try #require(shortlist.candidates.dropFirst().first)
        var analyses: [AssetID: RepresentativeAnalysis] = [:]
        for id in first.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 0, isUtility: true) }
        // `second` has no analyses at all: as if only in iCloud.
        let refined = discovery.refine(shortlist, analyses: analyses)
        #expect(!refined.contains { $0.id == first.id }, "receipts and documents aren't moments")
        let unavailable = try #require(refined.first { $0.id == second.id })
        #expect(unavailable.faces == .unknown)
        #expect(unavailable.unavailableRepresentatives == unavailable.representativeIDs.count)
        #expect(unavailable.score == unavailable.metadataScore, "no thumbnail: metadata ranking unchanged")
    }

    @Test func friendGroupsAndPagesOfNotesStepAsideForTheTwoOfYou() throws {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let candidates = shortlist.candidates.filter { $0.representativeIDs.count >= 2 }
        try #require(candidates.count >= 3)
        let (pair, group, notes) = (candidates[0], candidates[1], candidates[2])
        var analyses: [AssetID: RepresentativeAnalysis] = [:]
        for id in shortlist.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 0, aesthetic: 0.5) }
        for id in pair.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 2, aesthetic: 0.5) }
        for id in group.representativeIDs { analyses[id] = RepresentativeAnalysis(faceCount: 5, aesthetic: 0.5) }
        // Half of the moment is pages of a notebook.
        for (index, id) in notes.representativeIDs.enumerated() {
            analyses[id] = RepresentativeAnalysis(faceCount: 0, isUtility: index % 2 == 0, aesthetic: 0.5)
        }
        let refined = discovery.refine(shortlist, analyses: analyses)
        let kept = try #require(refined.first { $0.id == pair.id })
        #expect(kept.score > pair.metadataScore + 2, "photos of two people raise a moment")
        #expect(!refined.contains { $0.id == group.id }, "a moment of group photos only is more likely friends")
        #expect(!refined.contains { $0.id == notes.id }, "a moment that is mostly pages isn't a memory")
    }

    @Test func refinedCandidatesAreBoundedAndNewestFirst() {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let refined = discovery.refine(shortlist, analyses: [:])
        #expect(refined.count <= DiscoveryConfiguration.standard.maximumCandidates)
        #expect(refined.map(\.start) == refined.map(\.start).sorted(by: >))
    }

    @Test func onlyKeptMomentsAreImported() throws {
        let shortlist = discovery.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let refined = discovery.refine(shortlist, analyses: [:])
        let kept = Array(refined.prefix(2))
        let rejected = Array(refined.dropFirst(2))
        let imported = Set(discovery.importIdentifiers(for: kept))
        #expect(imported == Set(kept.flatMap(\.assetIDs)))
        #expect(imported.isDisjoint(with: Set(rejected.flatMap(\.assetIDs))))
    }

    @Test func aVeryLargeSelectionIsSpreadNotTruncated() {
        var configuration = DiscoveryConfiguration.standard
        configuration.maximumImportedAssets = 10
        let capped = MemoryDiscovery(configuration: configuration, calendar: testCalendar)
        let shortlist = capped.shortlist(from: F.library(), relationshipStart: nil, now: F.now)
        let kept = capped.refine(shortlist, analyses: [:])
        let imported = capped.importIdentifiers(for: kept)
        #expect(imported.count <= 10)
        #expect(Set(imported).isSubset(of: Set(kept.flatMap(\.assetIDs))))
    }

    @Test func discoveryHoldsNoIdentity() {
        // What discovery knows about faces is a count bucket — no names, geometry or embeddings.
        let labels = Mirror(reflecting: RepresentativeAnalysis(faceCount: 2)).children.compactMap(\.label)
        #expect(Set(labels) == ["faceCount", "isUtility", "aesthetic"])
        let candidate = DiscoveryFixture.library().prefix(3).map(\.id)
        #expect(!candidate.isEmpty)
        let candidateLabels = Mirror(reflecting: MemoryDiscovery(calendar: testCalendar).makeCandidate(Array(DiscoveryFixture.library().prefix(3)), isTrip: false)).children.compactMap(\.label)
        for label in candidateLabels {
            #expect(!["person", "identity", "embedding", "name", "faceprint", "landmarks"].contains { label.localizedCaseInsensitiveContains($0) }, "\(label)")
        }
    }
}

@Suite("First Discovery: what Relive shows first")
struct FirstDiscoveryTests {
    typealias M = MadeForYouFixture

    @Test func aTripWithEnoughVarietyIsAMovie() throws {
        let fixture = IntelligenceFixture.mixedTrip()
        let suggestions = M.engine(fixture).suggestions()
        let first = try #require(FirstDiscoveryResolver().resolve(suggestions: suggestions, library: fixture.library))
        #expect(first.kind == .movie)
        #expect(first.suggestion?.creation == .movie)
        #expect(first.suggestion?.title == "Three days in Kaş & Kekova.")
    }

    @Test func withoutATripAStrongMonthIsARecap() throws {
        let fixture = IntelligenceFixture(moments: [
            M.moment("o1", "October Morning", 5, start: date(2026, 10, 2, 9), look: 0),
            M.moment("o2", "October Evening", 5, start: date(2026, 10, 9, 19), look: 10),
        ])
        let suggestions = M.engine(fixture).suggestions()
        let first = try #require(FirstDiscoveryResolver().resolve(suggestions: suggestions, library: fixture.library))
        #expect(first.kind == .recap)
        #expect(first.suggestion?.creation == .monthlyRecap)
    }

    @Test func withNoSuggestionTheStrongestMomentLeads() throws {
        let fixture = IntelligenceFixture(moments: [
            M.moment("a", "June Evening", 6, start: date(2026, 6, 2, 19), look: 0),
            M.moment("b", "July Morning", 2, start: date(2026, 7, 9, 9), look: 10),
        ])
        let first = try #require(FirstDiscoveryResolver().resolve(suggestions: [], library: fixture.library))
        #expect(first.kind == .moment)
        #expect(first.momentID == IntelligenceFixture.momentID("a"))
        #expect(first.coverAssetID != nil)
    }

    @Test func aSmallLibraryStillGetsAResult() throws {
        let fixture = IntelligenceFixture(moments: [M.moment("s", "Saturday", 3, start: date(2026, 9, 5, 12), look: 0)])
        let first = try #require(FirstDiscoveryResolver().resolve(suggestions: [], library: fixture.library))
        #expect(first.kind == .smallStory)
        #expect(first.momentID == IntelligenceFixture.momentID("s"))
    }

    @Test func anEmptyStoryHasNothingToShow() {
        let fixture = IntelligenceFixture(moments: [])
        #expect(FirstDiscoveryResolver().resolve(suggestions: [], library: fixture.library) == nil)
    }
}

@Suite("Relationship start: what 'together since' may include")
struct RelationshipStartTimelineTests {
    typealias M = MadeForYouFixture

    @Test func momentsBeforeTheStartAreTheirOwnSectionFirst() {
        let fixture = IntelligenceFixture(moments: [
            M.moment("old", "Inverness", 3, start: date(2012, 3, 13, 11), look: 0),
            M.moment("new1", "June Evening", 3, start: date(2025, 6, 2, 19), look: 10),
            M.moment("new2", "Kaş", 3, start: date(2026, 8, 6, 10), look: 20),
        ])
        let story = fixture.library.story
        let sections = TimelineBuilder(calendar: testCalendar).sections(for: story, isVisible: { _ in true }, storyStart: date(2025, 3, 1), beforeStartTitle: "Before March 2025")
        #expect(sections.first?.id == TimelineBuilder.beforeStartID)
        #expect(sections.first?.title == "Before March 2025")
        #expect(sections.first?.items.count == 1)
        #expect(sections.dropFirst().map(\.title) == ["2025", "2026"])
        // A moment on the start day itself belongs to the story.
        let onTheDay = TimelineBuilder(calendar: testCalendar).sections(for: story, isVisible: { _ in true }, storyStart: date(2025, 6, 2, 23))
        #expect(onTheDay.first?.id == TimelineBuilder.beforeStartID)
        #expect(onTheDay.first?.items.count == 1)
    }

    @Test func withoutAStartNothingIsSetApart() {
        let fixture = IntelligenceFixture(moments: [
            M.moment("old", "Inverness", 3, start: date(2012, 3, 13, 11), look: 0),
            M.moment("new", "June Evening", 3, start: date(2025, 6, 2, 19), look: 10),
        ])
        let sections = TimelineBuilder(calendar: testCalendar).sections(for: fixture.library.story, isVisible: { _ in true })
        #expect(!sections.contains { $0.id == TimelineBuilder.beforeStartID })
        #expect(sections.map(\.title) == ["2012", "2025"])
    }
}

@Suite("Processing facts are only what the run found")
struct ProcessingFactsTests {
    @Test func factsAreReportedOnceKnown() async throws {
        let fixture = MemoryEngineFixtureForFacts.assets()
        let collected = FactsLog()
        let engine = MemoryEngine(
            configuration: MemoryEngineConfiguration(calendar: testCalendar),
            analyzer: NoAnalysis(),
            placeResolver: NoPlaces(),
            namingService: LocalMomentNamingService(calendar: testCalendar, locale: Locale(identifier: "en_US"))
        )
        let result = try await engine.buildStory(from: fixture, now: date(2026, 10, 14)) { progress in
            collected.append(progress)
        }
        let withMoments = collected.items.compactMap(\.facts.moments)
        #expect(!withMoments.isEmpty)
        #expect(withMoments.last == result.story.moments.count)
        // Before grouping, nothing is claimed.
        #expect(collected.items.filter { $0.stage == .analyzingImages }.allSatisfy { $0.facts.moments == nil })
    }
}

enum MemoryEngineFixtureForFacts {
    static func assets() -> [MemoryAsset] {
        DiscoveryFixture.burst("a", 4, start: date(2026, 5, 2, 19)) + DiscoveryFixture.burst("b", 4, start: date(2026, 5, 9, 9))
    }
}

final class FactsLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [MemoryEngineProgress] = []
    func append(_ progress: MemoryEngineProgress) { lock.withLock { stored.append(progress) } }
    var items: [MemoryEngineProgress] { lock.withLock { stored } }
}

struct NoAnalysis: AssetAnalyzing {
    func analyze(_ asset: MemoryAsset) async -> AssetAnalysis { .unavailable() }
}

struct NoPlaces: PlaceNameResolving {
    func placeName(for coordinate: GeoCoordinate) async -> PlaceName? { nil }
}
