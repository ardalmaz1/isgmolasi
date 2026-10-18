import Foundation
import Testing
@testable import ReliveCore

/// Real Device Product Polish V1: the archive index, Today's discoveries, the film selection
/// ("Make it for me" really remakes the cut), "Don't suggest" and no Relive branding.
enum PolishFixture {
    typealias F = IntelligenceFixture

    /// A distinct look per index, far apart from every other (wider than the shared fixture's
    /// 64 looks, so a 200-photo source has no accidental look-alikes).
    static func look(_ index: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: 256)
        vector[index % 256] = 1
        return vector
    }

    /// A four-day trip with `perDay` distinct photos a day (Kaş-sized with 55: 220 memories).
    static func bigTrip(perDay: Int = 55, hiddenDay: Int? = nil) -> IntelligenceFixture {
        var moments: [F.MomentSpec] = []
        for day in 0..<4 {
            var shots: [F.Shot] = []
            for index in 0..<perDay {
                let when = date(2025, 8, 6 + day, 8).addingTimeInterval(Double(index) * 700)
                let quality = 0.4 + Double((index * 7 + day * 3) % 11) / 20
                shots.append(F.Shot(id: "k\(day)-\(index)", date: when, portrait: index % 3 != 0, look: look(day * perDay + index), faces: index % 5 == 0 ? 2 : 0, quality: quality))
            }
            moments.append(F.MomentSpec(key: "k\(day)", title: "Kaş", shots: shots, place: day == 2 ? "Kekova" : "Kaş", trip: "Kaş", hidden: day == hiddenDay))
        }
        return IntelligenceFixture(moments: moments)
    }

    static func planner(_ library: CreationLibrary) -> MovieStoryPlanner {
        MovieStoryPlanner(library: library)
    }
}

@Suite("Polish: Memory Movie selection")
struct MovieSelectionPolishTests {
    typealias P = PolishFixture
    typealias F = IntelligenceFixture

    @Test func aLargeTripIsCoveredDayByDay() {
        let library = P.bigTrip().library
        let plan = P.planner(library).plan(source: .trip(F.tripID("Kaş")))
        #expect(plan.isReady)
        #expect(plan.scenes.count == MovieLength.standard.sceneCap, "15 photos from 220")
        let days = Set(plan.photoIDs.compactMap { library.assets[$0]?.creationDate }.map { testCalendar.component(.day, from: $0) })
        #expect(days == [6, 7, 8, 9], "every day of the trip is in the film")
    }

    @Test func makeItForMeChoosesAMeaningfullyDifferentSet() {
        let library = P.bigTrip().library
        let planner = P.planner(library)
        let first = planner.plan(source: .trip(F.tripID("Kaş")))
        let again = planner.plan(source: .trip(F.tripID("Kaş")), settings: MovieSettings(variation: 1), avoiding: Set(first.photoIDs))
        #expect(again.scenes.count == first.scenes.count)
        let repeated = Set(again.photoIDs).intersection(first.photoIDs).count
        #expect(repeated <= first.photoIDs.count / 2, "at most half the photos repeat (\(repeated))")
        #expect(repeated < first.photoIDs.count, "not the same photos reordered")
        // Still a film of the trip: every day, in the order the photos were taken after the opening.
        let days = Set(again.photoIDs.compactMap { library.assets[$0]?.creationDate }.map { testCalendar.component(.day, from: $0) })
        #expect(days == [6, 7, 8, 9])
        let body = again.photoIDs.dropFirst().compactMap { library.assets[$0]?.creationDate }
        #expect(body == body.sorted(), "chronological after the opening")
        // Deterministic.
        #expect(planner.plan(source: .trip(F.tripID("Kaş")), settings: MovieSettings(variation: 1), avoiding: Set(first.photoIDs)).photoIDs == again.photoIDs)
    }

    @Test func aSmallSourceMayKeepTheSamePhotos() {
        let fixture = IntelligenceFixture.smallMoment()
        let planner = MovieStoryPlanner(library: fixture.library)
        let source = CreationSource.moment(F.momentID("small"))
        let first = planner.plan(source: source, settings: MovieSettings(length: .short))
        let again = planner.plan(source: source, settings: MovieSettings(length: .short, variation: 1), avoiding: Set(first.photoIDs))
        #expect(Set(again.photoIDs) == Set(first.photoIDs), "five photos: nothing better to swap in")
        #expect(again.isReady)
    }

    @Test func hiddenAndNotSuggestedMemoriesAreNeverChosen() {
        var library = P.bigTrip(hiddenDay: 3).library
        let excluded: Set<AssetID> = Set((0..<55).map { "k1-\($0)" }.filter { $0.hasSuffix("0") || $0.hasSuffix("5") })
        library.suggestionExcludedAssetIDs = excluded
        let planner = P.planner(library)
        let first = planner.plan(source: .trip(F.tripID("Kaş")))
        let again = planner.plan(source: .trip(F.tripID("Kaş")), settings: MovieSettings(variation: 1), avoiding: Set(first.photoIDs))
        for plan in [first, again] {
            #expect(!plan.photoIDs.contains { $0.hasPrefix("k3-") }, "hidden day never used")
            #expect(plan.photoIDs.allSatisfy { !excluded.contains($0) }, "not suggested")
        }
        // A photo the user picks by hand is still used.
        let picked = planner.plan(source: .photos(Array(excluded.sorted().prefix(5))))
        #expect(picked.photoIDs.count == 5)
    }

    @Test func lookAlikesGiveWayToOtherScenes() {
        // One day: six strong scenes each shot again three hours later (look-alikes, not a
        // burst), and twelve other scenes. A short film has room for nine.
        var shots: [F.Shot] = []
        for index in 0..<6 {
            shots.append(F.Shot(id: "scene-\(index)", date: date(2026, 4, 4, 8).addingTimeInterval(Double(index) * 600), look: P.look(index), quality: 0.85))
            shots.append(F.Shot(id: "again-\(index)", date: date(2026, 4, 4, 11).addingTimeInterval(Double(index) * 600), look: P.look(index), quality: 0.85))
        }
        for index in 0..<12 {
            shots.append(F.Shot(id: "other-\(index)", date: date(2026, 4, 4, 15).addingTimeInterval(Double(index) * 600), look: P.look(100 + index), quality: 0.7))
        }
        let library = IntelligenceFixture(moments: [F.MomentSpec(key: "day", title: "Bergama", shots: shots, place: "Bergama")]).library
        let plan = MovieStoryPlanner(library: library).plan(source: .moment(F.momentID("day")), settings: MovieSettings(length: .short))
        #expect(plan.scenes.count == 9)
        for index in 0..<6 {
            let both = plan.photoIDs.contains("scene-\(index)") && plan.photoIDs.contains("again-\(index)")
            #expect(!both, "scene \(index) appears twice")
        }
    }

    @Test func otherCreationsKeepTheirSelection() {
        // The film rules are the film's: a collage from the same trip is chosen as before.
        let library = P.bigTrip().library
        let engine = MemoryIntelligenceEngine(library: library)
        let standard = engine.plan(for: .trip(F.tripID("Kaş")), target: .collage)
        let explicit = engine.plan(for: .trip(F.tripID("Kaş")), target: .collage, isFilm: false, avoiding: [])
        #expect(standard == explicit)
    }

    @Test func aPersonalMovieCarriesNoBranding() {
        let plan = P.planner(P.bigTrip().library).plan(source: .trip(F.tripID("Kaş")))
        let words = plan.scenes.compactMap(\.text).flatMap(\.all)
        #expect(!words.isEmpty)
        #expect(!words.contains { $0.localizedCaseInsensitiveContains("relive") })
    }

    @Test func aRecapClosingCarriesNoBranding() {
        let closing = DeterministicEditorialTextProvider().text(for: .closing(periodName: "August", isYear: false, memories: 31, moments: 4, places: 2))
        #expect(closing.eyebrow == nil)
        #expect(![closing.eyebrow, closing.title, closing.detail].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains("relive") })
    }

    @Test func film220PhotosIsQuick() {
        let library = P.bigTrip().library
        let planner = P.planner(library)
        let start = Date()
        let first = planner.plan(source: .trip(F.tripID("Kaş")))
        _ = planner.plan(source: .trip(F.tripID("Kaş")), settings: MovieSettings(variation: 1), avoiding: Set(first.photoIDs))
        let elapsed = Date().timeIntervalSince(start)
        print("MOVIE_POLISH plan+remake 220 photos: \(String(format: "%.3f", elapsed))s")
        #expect(elapsed < 10)
    }
}

@Suite("Polish: archive index")
struct ArchiveIndexTests {
    typealias F = IntelligenceFixture

    @Test func countsMatchUsAndHiddenDuplicatesAreLeftOut() {
        var fixture = PolishFixture.bigTrip(perDay: 6, hiddenDay: 1)
        fixture.moments[0].shots.append(F.Shot(id: "copy", date: date(2025, 8, 6, 20), look: PolishFixture.look(250), quality: 0.3))
        fixture.moments[0].duplicates = ["copy"]
        fixture.unavailable = ["k2-0"]
        let library = fixture.library
        let index = ArchiveIndex.build(story: library.story, assets: library.assets, userStates: library.userStates, isAvailable: library.isAvailable, calendar: testCalendar)
        let statistics = StoryStatistics.compute(story: library.story, assets: library.assets, userStates: library.userStates, isAvailable: library.isAvailable)
        #expect(index.memoryCount == statistics.memoryCount)
        #expect(index.memoryCount == 6 + 5 + 6, "day 2 hidden, one unavailable, the copy left out")
        #expect(index.allAssetIDs.count == index.memoryCount)
        #expect(!index.allAssetIDs.contains("copy"))
        #expect(!index.allAssetIDs.contains { $0.hasPrefix("k1-") })
        #expect(index.momentIDs.count == statistics.momentCount)
        #expect(index.places.count == statistics.placeCount)
    }

    @Test func monthsNewestFirstMemoriesInOrderInside() {
        let fixture = IntelligenceFixture(moments: [
            .init(key: "a", title: "A", shots: [.init(id: "a1", date: date(2024, 12, 31, 22), look: PolishFixture.look(1)), .init(id: "a0", date: date(2024, 12, 31, 21), look: PolishFixture.look(2))]),
            .init(key: "b", title: "B", shots: [.init(id: "b1", date: date(2025, 3, 3), look: PolishFixture.look(3))]),
            .init(key: "u", title: "U", shots: [.init(id: "u1", date: nil, look: PolishFixture.look(4))]),
        ])
        let library = fixture.library
        let index = ArchiveIndex.build(story: library.story, assets: library.assets, userStates: library.userStates, isAvailable: { _ in true }, calendar: testCalendar)
        #expect(index.months.map(\.id) == ["2025-03", "2024-12", "undated"])
        #expect(index.months[1].assetIDs == ["a0", "a1"])
        #expect(index.momentIDs.first == F.momentID("b"), "newest moment first")
        #expect(index.momentIDs.last == F.momentID("u"), "undated last")
    }

    @Test func placesAreGroupedLikeTheCountAndNeverInvented() {
        func moment(_ key: String, _ day: Int, place: String?, at coordinate: GeoCoordinate?) -> Moment {
            Moment(id: F.momentID(key), kind: .event, assetIDs: [key], featuredAssetIDs: [key], startDate: date(2025, day, 1), endDate: date(2025, day, 1), centroid: coordinate, place: place.map { PlaceName(name: $0) })
        }
        let kas = GeoCoordinate(latitude: 36.2, longitude: 29.64)
        let nearKas = GeoCoordinate(latitude: 36.21, longitude: 29.65)
        let farAway = GeoCoordinate(latitude: 39.12, longitude: 27.18)
        let moments = [
            moment("m1", 1, place: "Kaş", at: kas),
            moment("m2", 3, place: "kas", at: kas),
            moment("m3", 5, place: nil, at: nearKas),
            moment("m4", 7, place: nil, at: farAway),
            moment("m5", 9, place: nil, at: nil),
        ]
        let story = Story(generatedAt: date(2025, 10, 1), moments: moments, chapters: [])
        let assets = Dictionary(uniqueKeysWithValues: moments.map { ($0.assetIDs[0], makeAsset($0.assetIDs[0], at: $0.startDate)) })
        let index = ArchiveIndex.build(story: story, assets: assets, userStates: [:], isAvailable: { _ in true }, calendar: testCalendar)
        let statistics = StoryStatistics.compute(story: story, assets: assets, userStates: [:], isAvailable: { _ in true })
        #expect(index.places.count == statistics.placeCount)
        #expect(index.places.count == 2)
        let kasPlace = index.places.first { $0.name?.name == "Kaş" }
        #expect(kasPlace?.momentIDs == [F.momentID("m1"), F.momentID("m2"), F.momentID("m3")])
        #expect(kasPlace?.monthCount == 3)
        let unnamed = index.places.first { $0.name == nil }
        #expect(unnamed?.momentIDs == [F.momentID("m4")], "an unnamed place stays unnamed")
    }

    @Test func aThousandMemoriesIndexQuickly() {
        let fixture = PolishFixture.bigTrip(perDay: 250)
        let library = fixture.library
        let start = Date()
        let index = ArchiveIndex.build(story: library.story, assets: library.assets, userStates: library.userStates, isAvailable: library.isAvailable, calendar: testCalendar)
        let elapsed = Date().timeIntervalSince(start)
        print("ARCHIVE_INDEX memories=\(index.memoryCount) \(String(format: "%.3f", elapsed))s")
        #expect(index.memoryCount == 1_000)
        #expect(elapsed < 2)
    }
}

@Suite("Polish: Today discoveries")
struct TodayPlannerTests {
    typealias F = IntelligenceFixture

    static func fixture() -> IntelligenceFixture {
        IntelligenceFixture(moments: [
            // A year ago (Oct 16 2025, two days from "today" Oct 18 2026), Bergama.
            .init(key: "bergama", title: "Bergama", shots: [.init(id: "b1", date: date(2025, 10, 16, 11), look: PolishFixture.look(1))], place: "Bergama"),
            // A trip in August 2025: two moments.
            .init(key: "kas1", title: "Kaş", shots: [.init(id: "k1", date: date(2025, 8, 6, 11), look: PolishFixture.look(2))], place: "Kaş", trip: "Kaş"),
            .init(key: "kas2", title: "Kekova", shots: [.init(id: "k2", date: date(2025, 8, 8, 11), look: PolishFixture.look(3))], place: "Kekova", trip: "Kaş"),
            // Fethiye in May and July 2026: a place they returned to.
            .init(key: "f1", title: "Fethiye", shots: [.init(id: "f1", date: date(2026, 5, 2, 11), look: PolishFixture.look(4))], place: "Fethiye"),
            .init(key: "f2", title: "Fethiye", shots: [.init(id: "f2", date: date(2026, 7, 9, 11), look: PolishFixture.look(5))], place: "Fethiye"),
            // Recent: early October 2026.
            .init(key: "recent", title: "Çankaya", shots: [.init(id: "r1", date: date(2026, 10, 4, 11), look: PolishFixture.look(6))], place: "Çankaya"),
        ])
    }

    static func discoveries(_ fixture: IntelligenceFixture, excluding: Set<MomentID> = [], maximum: Int = 4, now: Date = date(2026, 10, 18, 9)) -> [TodayDiscovery] {
        let library = fixture.library
        let index = ArchiveIndex.build(story: library.story, assets: library.assets, userStates: library.userStates, isAvailable: library.isAvailable, calendar: testCalendar)
        return TodayPlanner(calendar: testCalendar, maximumItems: maximum).discoveries(
            story: library.story, visibleMoments: library.visibleMoments, places: index.places, excluding: excluding, now: now
        )
    }

    @Test func eachKindComesFromRealData() {
        let items = Self.discoveries(Self.fixture())
        #expect(items == [
            .onThisDay(F.momentID("bergama"), yearsAgo: 1),
            .trip(F.tripID("Kaş")),
            .returnedPlace(placeID: "fethiye"),
            .recentMoment(F.momentID("recent")),
        ])
    }

    @Test func todayStaysShortAndNeverRepeatsAMoment() {
        #expect(Self.discoveries(Self.fixture(), maximum: 2).count == 2, "two discoveries at most by default")
        let items = Self.discoveries(Self.fixture(), excluding: [F.momentID("bergama"), F.momentID("kas2")])
        #expect(!items.contains(.onThisDay(F.momentID("bergama"), yearsAgo: 1)), "the hero's moment isn't repeated")
        #expect(!items.contains(.trip(F.tripID("Kaş"))), "a trip already on Today isn't offered again")
    }

    @Test func nothingIsInventedForASmallNewStory() {
        let fixture = IntelligenceFixture(moments: [
            .init(key: "only", title: "Home", shots: [.init(id: "o1", date: date(2026, 2, 1, 11), look: PolishFixture.look(1))]),
        ])
        #expect(Self.discoveries(fixture).isEmpty, "no anniversary, trip, return or recent moment")
    }

    @Test func hiddenMomentsNeverAppear() {
        var fixture = Self.fixture()
        fixture.moments[0].hidden = true
        #expect(!Self.discoveries(fixture).contains { if case .onThisDay = $0 { return true } else { return false } })
    }

    @Test func stableForTheDay() {
        let morning = Self.discoveries(Self.fixture(), now: date(2026, 10, 18, 8))
        let evening = Self.discoveries(Self.fixture(), now: date(2026, 10, 18, 21))
        #expect(morning == evening)
    }
}

@Suite("Polish: Don't suggest and Found for You")
struct NotSuggestedTests {
    @Test func foundForYouNeverBringsBackANotSuggestedMemory() {
        let fixture = IntelligenceFixture(moments: [
            .init(key: "old", title: "Kaş", shots: [
                .init(id: "x1", date: date(2023, 8, 6, 11), look: PolishFixture.look(1), quality: 0.9),
                .init(id: "x2", date: date(2023, 8, 6, 12), look: PolishFixture.look(2), quality: 0.4),
            ], place: "Kaş"),
        ])
        let library = fixture.library
        let service = FoundForYouService(calendar: testCalendar)
        let found = service.select(story: library.story, assets: library.assets, userStates: [:], isAvailable: { _ in true }, now: date(2026, 10, 18), notSuggested: ["x1"])
        #expect(found?.assetID == "x2")
        let none = service.select(story: library.story, assets: library.assets, userStates: [:], isAvailable: { _ in true }, now: date(2026, 10, 18), notSuggested: ["x1", "x2"])
        #expect(none == nil)
    }
}

@Suite("Polish: the archive is never Premium")
struct ArchivePolicyTests {
    @Test func premiumOnlyCoversWhatReliveMakes() {
        // Locks the list: a capability for browsing memories, moments, places, the story,
        // favorites or hidden memories must never be added.
        #expect(Set(PremiumCapability.allCases.map(\.rawValue)) == [
            "collage_export", "story_export", "trend_export", "memory_book_export",
            "full_monthly_recap", "full_year_in_review", "premium_styles", "memory_movie",
            "made_for_you", "relive_ai", "anniversary_creations",
        ])
        for capability in PremiumCapability.allCases {
            for word in ["memory_browse", "archive", "moment", "place", "timeline", "favorite", "hidden"] {
                #expect(!capability.rawValue.contains(word))
            }
        }
    }

    @Test func premiumStillControlsItsOutputs() {
        let allowance = FreeCreationAllowance(usedAt: date(2026, 1, 1), usedFor: .collageExport)
        for capability in [PremiumCapability.memoryMovie, .memoryBookExport, .fullMonthlyRecap, .fullYearInReview, .collageExport] {
            #expect(PremiumPolicy.exportDecision(for: capability, isPremium: false, allowance: allowance) == .requiresPremium)
            #expect(PremiumPolicy.exportDecision(for: capability, isPremium: true, allowance: allowance) == .allowed)
        }
        #expect(!PremiumPolicy.hasAccess(to: .fullMonthlyRecap, isPremium: false))
    }
}
