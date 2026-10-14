import ReliveCore
import XCTest
@testable import Relive

// Made for You through the real StoryStore, AppModel, PremiumStore and gate. The creation test
// story has a 9-photo Kaş moment exactly one year before its "now".

@MainActor
final class MadeForYouAppTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = PremiumTestKit.defaults()
    }

    private func makeStore() -> MadeForYouStore {
        MadeForYouStore(defaults: defaults, now: { CreationTestLibrary.now })
    }

    func testAnAnniversaryIsSuggestedAndStrongEnoughForToday() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let first = try XCTUnwrap(madeForYou.suggestions.first)
        XCTAssertEqual(first.kind, .anniversary)
        XCTAssertEqual(first.eyebrow, "A year ago today")
        XCTAssertEqual(first.title, "Kaş")
        XCTAssertTrue(first.assetIDs.allSatisfy { $0.hasPrefix("trip-") }, "only that moment's memories")
        XCTAssertEqual(madeForYou.todaySuggestion(excluding: nil)?.id, first.id)
        XCTAssertNil(madeForYou.todaySuggestion(excluding: first.momentID), "Today never repeats the surprise's moment")
    }

    func testNoStoryNoSuggestions() {
        let repository = InMemoryStoryRepository(assets: [])
        let store = StoryStore(repository: repository, photoLibrary: FakePhotoLibrary(assets: []), analyzer: InstantAnalyzer(), placeResolver: NoPlaceLookups(), analytics: InMemoryAnalyticsTracker())
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        XCTAssertTrue(madeForYou.suggestions.isEmpty, "nothing while there's no story (or it is still being built)")
    }

    func testDismissalPersistsAndTheNextBestTakesItsPlace() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let dismissed = try XCTUnwrap(madeForYou.suggestions.first)
        madeForYou.dismiss(dismissed, store: store)
        XCTAssertFalse(madeForYou.suggestions.map(\.id).contains(dismissed.id))

        // A relaunch remembers it.
        let relaunched = makeStore()
        relaunched.refresh(from: store)
        XCTAssertFalse(relaunched.suggestions.map(\.id).contains(dismissed.id))
        XCTAssertNotNil(relaunched.history.entries[dismissed.id]?.dismissedAt)
    }

    func testShownAndOpenedAreRemembered() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let first = try XCTUnwrap(madeForYou.suggestions.first)
        madeForYou.recordShown(madeForYou.suggestions)
        madeForYou.recordShown(madeForYou.suggestions)
        madeForYou.recordOpened(first)
        let relaunched = makeStore()
        XCTAssertEqual(relaunched.history.entries[first.id]?.shownDays, 1, "once per day")
        XCTAssertNotNil(relaunched.history.entries[first.id]?.openedAt)
    }

    func testMakingSomethingFromASuggestionRetiresIt() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let first = try XCTUnwrap(madeForYou.suggestions.first)
        madeForYou.recordShown([first])

        // The couple makes a book from the same moment (kept creations record their source).
        let book = try MemoryBookBuilder(library: store.creationLibrary).makeBook(from: first.source, now: Date()).get()
        store.saveBook(book)
        madeForYou.refresh(from: store)
        XCTAssertFalse(madeForYou.suggestions.map(\.id).contains(first.id))
        XCTAssertNotNil(madeForYou.history.entries[first.id]?.createdAt)
    }

    func testLibraryChangesRefreshSuggestions() throws {
        let (store, _) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let anniversary = try XCTUnwrap(madeForYou.suggestions.first { $0.kind == .anniversary })
        let momentID = try XCTUnwrap(anniversary.momentID)

        // Hiding the moment removes it at the next refresh.
        store.setHidden(true, for: momentID)
        madeForYou.refresh(from: store)
        XCTAssertFalse(madeForYou.suggestions.contains { $0.momentID == momentID })
        store.setHidden(false, for: momentID)
        madeForYou.refresh(from: store)
        XCTAssertTrue(madeForYou.suggestions.contains { $0.momentID == momentID })
    }

    func testOpeningASuggestionNeverAsksForPremiumAndExportRulesStayTheSame() async throws {
        let (store, repository) = CreationTestLibrary.makeStore()
        let madeForYou = makeStore()
        madeForYou.refresh(from: store)
        let suggestion = try XCTUnwrap(madeForYou.suggestions.first { $0.creation == .collage })
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        var pushed: [CreateRoute] = []
        MadeForYouOpener.open(suggestion, app: app, madeForYou: madeForYou, origin: "made_for_you") { pushed.append($0) }
        XCTAssertEqual(app.activeCreation?.kind, .collage)
        XCTAssertEqual(app.activeCreation?.start, .source(suggestion.source))
        XCTAssertTrue(pushed.isEmpty)

        // The prepared collage is the plan's photos, editable as usual; nothing is saved yet.
        let library = store.creationLibrary
        let photos = library.initialPhotos(for: suggestion.source, limit: CreationLimits.collagePreselection)
        XCTAssertFalse(photos.isEmpty)
        XCTAssertTrue(store.keptItems.isEmpty, "opening never saves anything")

        // Free user: the first save is free, the second shows the paywall — unchanged rules.
        let premium = PremiumTestKit.store(defaults: defaults)
        let gate = PremiumGate()
        XCTAssertNil(gate.request, "opening asked for nothing")
        let export = ExportController(saver: FakeCreationSaver(identifiers: ["s1", "s2"]))
        await gate.export(.collageExport, entry: .collageExport, premium: premium) { succeeded in
            await export.save(store: store, analytics: InMemoryAnalyticsTracker(), properties: [:], onSaved: succeeded) {
                [CreationTestLibrary.solidImage(width: 8, height: 8)]
            }
        }
        XCTAssertEqual(export.phase, .finished("Saved to Photos"))
        await gate.export(.collageExport, entry: .collageExport, premium: premium) { _ in XCTFail("not without Premium") }
        XCTAssertEqual(gate.request?.entry, .collageExport)
    }

    func testRecapSuggestionsOpenTheExistingScreens() {
        let (store, repository) = CreationTestLibrary.makeStore()
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        let madeForYou = makeStore()
        let month = MadeForYouSuggestionFixture.make(creation: .monthlyRecap, source: .month(MonthKey(year: 2026, month: 7)))
        var pushed: [CreateRoute] = []
        MadeForYouOpener.open(month, app: app, madeForYou: madeForYou, origin: "test") { pushed.append($0) }
        XCTAssertEqual(pushed, [.month(MonthKey(year: 2026, month: 7))])
        XCTAssertNil(app.activeCreation)
        let year = MadeForYouSuggestionFixture.make(creation: .yearInReview, source: .year(2026))
        MadeForYouOpener.open(year, app: app, madeForYou: madeForYou, origin: "test") { pushed.append($0) }
        XCTAssertEqual(pushed.last, .year(2026))
    }

    func testChosenPhotoSuggestionsKeepExactlyTheirPhotos() {
        let (store, _) = CreationTestLibrary.makeStore()
        let chosen = ["trip-0", "trip-3", "evening-1"]
        XCTAssertEqual(store.creationLibrary.initialPhotos(for: .photos(chosen), limit: 6), chosen)
    }
}

/// A suggestion built by hand, for routing tests.
enum MadeForYouSuggestionFixture {
    static func make(creation: ReliveCore.CreationKind, source: CreationSource) -> MadeForYouSuggestion {
        let data = """
        {"id":"test:\(creation.rawValue)","kind":"monthRecap","eyebrow":"Your month","title":"Your July","subtitle":"10 memories",
         "creation":"\(creation.rawValue)","source":\(String(data: try! JSONEncoder().encode(source), encoding: .utf8)!),
         "assetIDs":[],"memoryCount":10,"coverage":[],"quality":2}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(MadeForYouSuggestion.self, from: data)
    }
}
