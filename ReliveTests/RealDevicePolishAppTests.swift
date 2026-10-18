import ReliveCore
import XCTest
@testable import Relive

// Real Device Product Polish V1 in the app: the free archive, "Don't suggest", draft identity,
// "Make it for me" and Today's discoveries.

@MainActor
enum PolishTestKit {
    static let calendar = Calendar.current
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))!

    /// A four-day trip with `perDay` photos a day (Kaş-like), plus a moment from a year ago.
    static func makeStore(perDay: Int = 15) -> (StoryStore, InMemoryStoryRepository) {
        var assets: [MemoryAsset] = []
        var moments: [Moment] = []
        let tripID = UUID()
        for day in 0..<4 {
            let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6 + day, hour: 9))!
            let members = (0..<perDay).map { index in
                MemoryAsset(
                    localIdentifier: "kas-\(day)-\(index)",
                    creationDate: start.addingTimeInterval(Double(index) * 900),
                    pixelWidth: index.isMultiple(of: 3) ? 4032 : 3024,
                    pixelHeight: index.isMultiple(of: 3) ? 3024 : 4032
                )
            }
            assets += members
            moments.append(Moment(
                id: UUID(), kind: .event, assetIDs: members.map(\.id), featuredAssetIDs: members.map(\.id),
                heroAssetID: members.first?.id, startDate: start, endDate: start.addingTimeInterval(Double(perDay) * 900),
                centroid: GeoCoordinate(latitude: 36.2, longitude: 29.64), place: PlaceName(name: "Kaş"),
                title: MomentTitle(primary: "Kaş"), chapterID: tripID
            ))
        }
        let yearAgo = calendar.date(from: DateComponents(year: 2025, month: 10, day: 17, hour: 12))!
        let bergama = (0..<4).map { MemoryAsset(localIdentifier: "bergama-\($0)", creationDate: yearAgo.addingTimeInterval(Double($0) * 600), pixelWidth: 3024, pixelHeight: 4032) }
        assets += bergama
        moments.insert(Moment(
            id: UUID(), kind: .event, assetIDs: bergama.map(\.id), featuredAssetIDs: bergama.map(\.id), heroAssetID: bergama.first?.id,
            startDate: yearAgo, endDate: yearAgo.addingTimeInterval(1_800), centroid: GeoCoordinate(latitude: 39.12, longitude: 27.18),
            place: PlaceName(name: "Bergama"), title: MomentTitle(primary: "Bergama")
        ), at: 0)
        let chapter = Chapter(id: tripID, momentIDs: moments.dropFirst().map(\.id), startDate: moments[1].startDate!, endDate: moments.last!.endDate!, place: PlaceName(name: "Kaş"), title: MomentTitle(primary: "Kaş"))
        let repository = InMemoryStoryRepository(assets: assets)
        repository.story = Story(generatedAt: now, moments: moments, chapters: [chapter])
        return (CollectionTestStore.reopen(repository), repository)
    }
}

@MainActor
final class FreeArchiveTests: XCTestCase {
    func testUsNumbersOpenExactlyThoseMemoriesMomentsAndPlaces() {
        let (store, _) = PolishTestKit.makeStore()
        XCTAssertEqual(store.archive.memoryCount, store.statistics.memoryCount)
        XCTAssertEqual(store.archive.allAssetIDs.count, store.statistics.memoryCount)
        XCTAssertEqual(store.archive.momentIDs.count, store.statistics.momentCount)
        XCTAssertEqual(store.archive.places.count, store.statistics.placeCount)
        XCTAssertEqual(store.archive.places.compactMap(\.name?.name).sorted(), ["Bergama", "Kaş"])
        XCTAssertEqual(store.archive.months.first?.id, "2026-08", "newest month first")
    }

    func testHidingAMomentTakesItOutOfTheArchiveAndUndoBringsItBack() throws {
        let (store, _) = PolishTestKit.makeStore()
        let before = store.archive.memoryCount
        let bergama = try XCTUnwrap(store.story.moments.first)
        store.setHidden(true, for: bergama.id)
        XCTAssertEqual(store.archive.memoryCount, before - 4)
        XCTAssertFalse(store.archive.momentIDs.contains(bergama.id))
        store.setHidden(false, for: bergama.id)
        XCTAssertEqual(store.archive.memoryCount, before)
    }

    /// The archive is never behind Premium: nothing in the archive path consults the
    /// entitlement, and Premium still controls what Relive makes.
    func testFreeUsersBrowseEverythingAndPremiumStillGuardsOutputs() {
        let (store, _) = PolishTestKit.makeStore()
        XCTAssertGreaterThan(store.archive.memoryCount, 0, "a free user's archive is all there")
        for capability in PremiumCapability.allCases {
            for word in ["archive", "moment", "place", "favorite", "hidden"] {
                XCTAssertFalse(capability.rawValue.contains(word), "\(capability.rawValue) would gate the archive")
            }
        }
        let used = FreeCreationAllowance(usedAt: PolishTestKit.now, usedFor: .collageExport)
        XCTAssertEqual(PremiumPolicy.exportDecision(for: .memoryMovie, isPremium: false, allowance: used), .requiresPremium)
        XCTAssertEqual(PremiumPolicy.exportDecision(for: .memoryBookExport, isPremium: false, allowance: used), .requiresPremium)
        XCTAssertFalse(PremiumPolicy.hasAccess(to: .fullMonthlyRecap, isPremium: false))
        XCTAssertFalse(PremiumPolicy.hasAccess(to: .fullYearInReview, isPremium: false))
    }
}

@MainActor
final class NotSuggestedAppTests: XCTestCase {
    func testDontSuggestIsKeptAndNeverChosenAutomatically() {
        let (store, repository) = PolishTestKit.makeStore()
        let excluded = (0..<15).map { "kas-1-\($0)" }
        for id in excluded { store.setNotSuggested(id, true) }
        XCTAssertEqual(repository.notSuggested, Set(excluded))

        let reopened = CollectionTestStore.reopen(repository)
        XCTAssertEqual(reopened.notSuggested, Set(excluded), "kept across a relaunch")
        XCTAssertEqual(reopened.archive.memoryCount, store.archive.memoryCount, "still in the story")
        let trip = reopened.story.chapters[0].id
        let plan = MovieStoryPlanner(library: reopened.creationLibrary).plan(source: .trip(trip))
        XCTAssertTrue(plan.isReady)
        XCTAssertTrue(plan.photoIDs.allSatisfy { !excluded.contains($0) }, "never in an automatic movie")

        reopened.setNotSuggested("kas-1-0", false)
        XCTAssertFalse(repository.notSuggested.contains("kas-1-0"))
    }

    func testStartOverKeepsThePrivacyChoice() {
        let (store, repository) = PolishTestKit.makeStore()
        store.setNotSuggested("kas-0-3", true)
        store.resetAll()
        XCTAssertTrue(repository.notSuggested.contains("kas-0-3"))
    }
}

@MainActor
final class DraftIdentityTests: XCTestCase {
    func testOpeningTheSameSourceContinuesItsDraft() throws {
        let (store, _) = PolishTestKit.makeStore()
        let trip = CreationSource.trip(store.story.chapters[0].id)
        XCTAssertNil(store.latestDraft(kind: .movie, source: trip))

        let first = MovieEditorModel(source: trip, library: store.creationLibrary, store: store)
        first.setStyle(.film)
        first.flush()
        let draft = try XCTUnwrap(store.latestDraft(kind: .movie, source: trip))
        XCTAssertEqual(draft.movie?.settings.style, .film)

        // The same trip's movie again: the flow continues this draft (no duplicate).
        XCTAssertEqual(store.latestDraft(kind: .movie, source: trip)?.id, draft.id)
        XCTAssertEqual(store.drafts.filter { $0.kind == .movie }.count, 1)
        // Another kind, or another source, is another creation.
        XCTAssertNil(store.latestDraft(kind: .collage, source: trip))
        XCTAssertNil(store.latestDraft(kind: .movie, source: .moment(store.story.moments[0].id)))
        // Chosen photos always start a new creation.
        XCTAssertNil(store.latestDraft(kind: .movie, source: .photos(["kas-0-0", "kas-0-1"])))

        // "Start New" makes another version on purpose; both are kept, the newest is continued.
        let second = MovieEditorModel(source: trip, library: store.creationLibrary, store: store)
        second.setStyle(.warm)
        second.flush()
        XCTAssertEqual(store.drafts.filter { $0.kind == .movie }.count, 2, "a deliberate second version is never merged")
        XCTAssertEqual(store.latestDraft(kind: .movie, source: trip)?.movie?.settings.style, .warm)
    }

    func testDeletingADraftKeepsItsPhotos() throws {
        let (store, _) = PolishTestKit.makeStore()
        let trip = CreationSource.trip(store.story.chapters[0].id)
        let model = MovieEditorModel(source: trip, library: store.creationLibrary, store: store)
        model.setStyle(.film)
        model.flush()
        let draft = try XCTUnwrap(store.drafts.first)
        let memories = store.archive.memoryCount
        store.deleteCreation(id: draft.id)
        XCTAssertTrue(store.drafts.isEmpty)
        XCTAssertEqual(store.archive.memoryCount, memories)
    }
}

@MainActor
final class MakeItForMeAppTests: XCTestCase {
    func testMakeItForMeRemakesTheCutAndKeepsTheUsersSettings() {
        let (store, _) = PolishTestKit.makeStore(perDay: 20)
        let trip = CreationSource.trip(store.story.chapters[0].id)
        let model = MovieEditorModel(source: trip, library: store.creationLibrary)
        model.setStyle(.editorial)
        model.setAspect(.landscape)
        let first = model.plan.photoIDs
        XCTAssertEqual(first.count, MovieLength.standard.sceneCap)

        model.makeItForMe()
        let second = model.plan.photoIDs
        XCTAssertEqual(model.plan.settings.style, .editorial, "style kept")
        XCTAssertEqual(model.plan.settings.aspect, .landscape, "shape kept")
        XCTAssertEqual(model.plan.settings.length, .standard, "length kept")
        XCTAssertEqual(second.count, first.count)
        XCTAssertLessThanOrEqual(Set(second).intersection(first).count, first.count / 2, "a meaningfully different set, not a reorder")
        let body = second.dropFirst().compactMap { store.assets[$0]?.creationDate }
        XCTAssertEqual(body, body.sorted(), "still told in order")
    }

    func testAUsersCutIsOnlyReplacedOnRequest() {
        let (store, _) = PolishTestKit.makeStore()
        let trip = CreationSource.trip(store.story.chapters[0].id)
        let model = MovieEditorModel(source: trip, library: store.creationLibrary)
        XCTAssertFalse(model.remakeReplacesUserEdits)
        model.remove(model.plan.photoIDs[2])
        XCTAssertTrue(model.remakeReplacesUserEdits, "the editor asks before Make it for me replaces it")
        let cut = model.plan.photoIDs
        model.setStyle(.film)
        model.setLength(.long)
        XCTAssertEqual(model.plan.photoIDs, cut, "unrelated actions never touch the user's cut")
    }

    func testDontSuggestFromTheEditorRemovesThePhotoForGood() throws {
        let (store, _) = PolishTestKit.makeStore()
        let trip = CreationSource.trip(store.story.chapters[0].id)
        let model = MovieEditorModel(source: trip, library: store.creationLibrary, store: store)
        let photo = model.plan.photoIDs[3]
        model.removeAndDontSuggest(photo, store: store)
        XCTAssertFalse(model.plan.photoIDs.contains(photo))
        XCTAssertTrue(store.isNotSuggested(photo))
        model.makeItForMe()
        XCTAssertFalse(model.plan.photoIDs.contains(photo), "not brought back by a new cut")
        XCTAssertFalse(model.replacementCandidates.isEmpty)
    }
}

@MainActor
final class TodayDiscoveryAppTests: XCTestCase {
    func testTodayOffersOnlyRealDiscoveries() {
        let (store, _) = PolishTestKit.makeStore()
        let items = TodayPlanner(calendar: PolishTestKit.calendar).discoveries(
            story: store.story, visibleMoments: store.visibleMoments, places: store.archive.places, excluding: [], now: PolishTestKit.now
        )
        XCTAssertLessThanOrEqual(items.count, 2)
        XCTAssertEqual(items.first, .onThisDay(store.story.moments[0].id, yearsAgo: 1), "a year ago · Bergama")
        XCTAssertEqual(items.dropFirst().first, .trip(store.story.chapters[0].id))
    }

    func testAnEmptyStoryHasNoDiscoveries() {
        let repository = InMemoryStoryRepository()
        let store = CollectionTestStore.reopen(repository)
        XCTAssertTrue(TodayPlanner(calendar: .current).discoveries(story: store.story, visibleMoments: store.visibleMoments, places: store.archive.places, excluding: [], now: Date()).isEmpty)
    }
}
