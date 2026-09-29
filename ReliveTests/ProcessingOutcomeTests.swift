import ReliveCore
import XCTest
@testable import Relive

/// How a processing run ends, independent of any screen: every caller gets an explicit outcome,
/// there is only ever one run, and a failed or cancelled run can never look successful.
@MainActor
final class ProcessingOutcomeTests: XCTestCase {
    func testSuccessfulRunReturnsFinishedAndKeepsThatState() async {
        let store = makeTestStore(assets: TestLibrary.assets(count: 120))

        let outcome = await store.process()

        guard case .finished(let diagnostics) = outcome else {
            return XCTFail("Expected success, got \(outcome)")
        }
        XCTAssertEqual(diagnostics.inputCount, 120)
        XCTAssertEqual(store.processing, .finished(diagnostics))
        XCTAssertTrue(store.hasStory)

        // Nothing still in flight (such as a late progress update) may replace the outcome.
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(store.processing, .finished(diagnostics))
    }

    func testCallersDuringARunShareThatRun() async throws {
        let analyzer = GatedAnalyzer()
        let assets = TestLibrary.assets(count: 30)
        let store = makeTestStore(assets: assets, analyzer: analyzer)

        let first = Task { await store.process() }
        try await waitUntil { analyzer.callCount > 0 }
        let second = Task { await store.process() }
        analyzer.open()

        let firstOutcome = await first.value
        let secondOutcome = await second.value
        guard case .finished = firstOutcome else {
            return XCTFail("Expected success, got \(firstOutcome)")
        }
        XCTAssertEqual(secondOutcome, firstOutcome, "The second caller should receive the same run's outcome")
        XCTAssertEqual(analyzer.callCount, assets.count, "The photos should have been analyzed once, not twice")
    }

    func testEmptySelectionFailsAndNeverReportsSuccess() async {
        let store = makeTestStore(assets: [])

        let outcome = await store.process()

        guard case .failed = outcome else {
            return XCTFail("Expected a failure, got \(outcome)")
        }
        guard case .failed = store.processing else {
            return XCTFail("Expected a failure state, got \(store.processing)")
        }
        XCTAssertFalse(store.hasStory)
    }

    func testStartOverDuringARunCancelsItWithoutApplyingItsResult() async throws {
        let analyzer = GatedAnalyzer()
        let store = makeTestStore(assets: TestLibrary.assets(count: 30), analyzer: analyzer)

        let run = Task { await store.process() }
        try await waitUntil { analyzer.callCount > 0 }
        store.resetAll()
        analyzer.open()

        let outcome = await run.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(store.processing, .idle, "A cancelled run must not leave a success or failure behind")
        XCTAssertFalse(store.hasStory, "A cancelled run's story must be discarded")
    }

    func testANewRunCanStartAfterAFailure() async {
        let assets = TestLibrary.assets(count: 20)
        let repository = InMemoryStoryRepository(assets: [])
        let store = StoryStore(
            repository: repository,
            photoLibrary: FakePhotoLibrary(assets: assets),
            analyzer: InstantAnalyzer(),
            placeResolver: NoPlaceLookups(),
            analytics: InMemoryAnalyticsTracker()
        )
        guard case .failed = await store.process() else {
            return XCTFail("An empty selection should fail")
        }

        await store.importSelection(identifiers: assets.map(\.id))
        let retry = await store.process()

        guard case .finished = retry else {
            return XCTFail("Try Again after adding photos should succeed, got \(retry)")
        }
    }
}
