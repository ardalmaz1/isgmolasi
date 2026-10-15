import ReliveCore
import XCTest
@testable import Relive

// Monthly Recap 2.0 / Our Year 2.0 in the app: presenting the immersive recap, the free preview's
// shape, creating from it and sharing it — through the real AppModel, PremiumStore, PremiumGate
// and MadeForYouStore (no PhotoKit, no live purchases).

@MainActor
final class RecapAppTests: XCTestCase {
    private var tripMonth: MonthKey {
        let calendar = CreationTestLibrary.calendar
        return MonthKey(date: calendar.date(byAdding: .year, value: -1, to: CreationTestLibrary.now)!, calendar: calendar)
    }

    /// A plan of the fixture month with the given chapter kinds (the real chapters' words and
    /// photos, so only the shape is made up).
    private func plan(_ kinds: [RecapChapter.Kind], isRich: Bool = true) -> RecapPlan {
        let (store, _) = CreationTestLibrary.makeStore()
        var plan = RecapStoryPlanner(library: store.creationLibrary).plan(.month(tripMonth))
        let template = plan.chapters[0]
        plan.isRich = isRich
        plan.chapters = kinds.enumerated().map { index, kind in
            var chapter = template
            chapter.id = "\(kind.rawValue)-\(index)"
            chapter.kind = kind
            return chapter
        }
        return plan
    }

    private func codes(_ pages: [RecapExperienceView.Page]) -> [String] {
        pages.map(\.code)
    }

    func testTheSmallFixtureMonthIsOneCompactPage() {
        let (store, _) = CreationTestLibrary.makeStore()
        let plan = RecapStoryPlanner(library: store.creationLibrary).plan(.month(tripMonth))
        XCTAssertEqual(plan.insights.memoryCount, 14)
        // Two moments, fewer than five true chapters: told as one compact page, not padded.
        XCTAssertFalse(plan.isRich)
        XCTAssertEqual(plan.chapters.map(\.kind), [.compactSummary])
        XCTAssertEqual(plan.creationSource, .month(tripMonth))
        XCTAssertFalse(plan.diagnosticsLine.contains("Kaş"), "diagnostics carry counts, never places")
        // Nothing from another period: the small moment is months later.
        XCTAssertFalse(plan.chapters.flatMap(\.photos).isEmpty)
        XCTAssertFalse(plan.chapters.flatMap(\.photos).contains { $0.hasPrefix("small") })
    }

    func testFreeUsersSeeTheOpeningAPreviewThePremiumPageAndTheClosing() {
        let kinds: [RecapChapter.Kind] = [.opening, .firstMemory, .tripHighlight, .placeHighlight, .visualGrid, .places, .closing]
        XCTAssertEqual(codes(RecapExperienceView.pages(for: plan(kinds), isFull: false)), ["opening", "firstMemory", "tripHighlight", "premium", "closing"])
        XCTAssertEqual(codes(RecapExperienceView.pages(for: plan(kinds), isFull: true)), kinds.map(\.rawValue))
    }

    func testSparseAndShortRecapsAreNeverGated() {
        let short: [RecapChapter.Kind] = [.opening, .firstMemory, .visualGrid, .closing]
        XCTAssertEqual(codes(RecapExperienceView.pages(for: plan(short), isFull: false)), short.map(\.rawValue))
        let compact: [RecapChapter.Kind] = [.compactSummary, .closing]
        XCTAssertEqual(codes(RecapExperienceView.pages(for: plan(compact, isRich: false), isFull: false)), compact.map(\.rawValue))
    }

    func testOpeningARecapNeverAsksForPremium() {
        let (store, repository) = CreationTestLibrary.makeStore()
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        app.openRecap(.year(2025), origin: "our_year")
        XCTAssertEqual(app.activeRecap?.period, .year(2025))
        XCTAssertEqual(app.activeRecap?.origin, "our_year")
        XCTAssertNil(app.activeCreation)
    }

    func testCreatingFromARecapClosesItThenOpensTheCreationWithTheRecapsSource() {
        let (store, repository) = CreationTestLibrary.makeStore()
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        app.openRecap(.month(tripMonth), origin: "made_for_you")
        app.startCreationFromRecap(.collage, source: .month(tripMonth))
        XCTAssertNil(app.activeRecap, "two full-screen covers can't stack: the recap closes first")
        XCTAssertNil(app.activeCreation)
        app.recapDismissed()
        XCTAssertEqual(app.activeCreation?.kind, .collage)
        XCTAssertEqual(app.activeCreation?.start, .source(.month(tripMonth)))
        XCTAssertEqual(app.activeCreation?.origin, "recap")
        // Nothing is saved by opening it.
        XCTAssertTrue(store.keptItems.isEmpty)

        // Closing a recap without creating opens nothing.
        app.activeCreation = nil
        app.openRecap(.month(tripMonth), origin: "monthly_recap")
        app.activeRecap = nil
        app.recapDismissed()
        XCTAssertNil(app.activeCreation)
    }

    func testSharingTheRecapCardFollowsTheExistingPremiumRule() async {
        let premium = PremiumTestKit.store()
        await premium.refreshEntitlements()
        let gate = PremiumGate()
        var shared = false
        await gate.export(.fullMonthlyRecap, entry: .monthlyRecap, premium: premium) { _ in shared = true }
        XCTAssertFalse(shared, "the recap card is part of the full recap")
        XCTAssertEqual(gate.request?.entry, .monthlyRecap)
        XCTAssertTrue(premium.allowance.isAvailable, "the free creation isn't spent on a recap")
        XCTAssertFalse(premium.hasAccess(to: .fullYearInReview))

        let client = FakeStoreKitClient()
        client.snapshot.transactions = [client.activeTransaction(.annual)]
        let subscriber = PremiumTestKit.store(client)
        await subscriber.refreshEntitlements()
        XCTAssertTrue(subscriber.hasAccess(to: .fullMonthlyRecap))
        XCTAssertTrue(subscriber.hasAccess(to: .fullYearInReview))
    }

    func testRecordingAMadeRecapOnlyTouchesThatPeriodsRecapSuggestion() {
        let (store, _) = CreationTestLibrary.makeStore()
        let defaults = PremiumTestKit.defaults()
        let madeForYou = MadeForYouStore(defaults: defaults, now: { CreationTestLibrary.now })
        madeForYou.refresh(from: store)
        let before = madeForYou.history
        madeForYou.recordMade(source: .month(MonthKey(year: 1999, month: 1)))
        XCTAssertEqual(madeForYou.history, before, "a period nothing was suggested for changes nothing")
        for suggestion in madeForYou.suggestions where suggestion.creation == .monthlyRecap || suggestion.creation == .yearInReview {
            madeForYou.recordMade(source: suggestion.source)
            XCTAssertNotNil(madeForYou.history.entries[suggestion.id]?.createdAt)
        }
        for suggestion in madeForYou.suggestions where suggestion.creation != .monthlyRecap && suggestion.creation != .yearInReview {
            XCTAssertNil(madeForYou.history.entries[suggestion.id]?.createdAt)
        }
    }
}
