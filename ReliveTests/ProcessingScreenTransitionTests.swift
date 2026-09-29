import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

/// Regression tests for the processing screen getting stuck on "Choosing a few favorites…"
/// after the pipeline had already finished (first real-device test: 53 photos in 2 seconds).
///
/// The real `ProcessingView` is rendered in a window, so SwiftUI's actual update cycle decides
/// what the screen sees — the part of the system where the bug lived. Before the fix,
/// `testFastPipelineLeavesProcessingScreenExactlyOnce` timed out with the store still holding
/// its unacknowledged `.finished` result.
@MainActor
final class ProcessingScreenTransitionTests: XCTestCase {
    /// A pipeline that completes within a frame or two must still take the user to the reveal —
    /// exactly once.
    func testFastPipelineLeavesProcessingScreenExactlyOnce() async throws {
        let store = makeTestStore(assets: TestLibrary.assets(count: 300))
        let revealed = expectation(description: "processing screen hands over to the reveal")
        revealed.assertForOverFulfill = true

        let window = try show(ProcessingView { revealed.fulfill() }, store: store)
        defer { window.isHidden = true }

        await fulfillment(of: [revealed], timeout: 15)
        XCTAssertTrue(store.hasStory, "The story should have been built and kept")
        XCTAssertEqual(store.processing, .idle, "The finished result should have been acknowledged")

        // Give any late, duplicate hand-over a chance to happen (over-fulfilment fails the test).
        try await Task.sleep(for: .milliseconds(500))
    }

    /// A failed pipeline must never look like success.
    func testFailedPipelineNeverLeavesProcessingScreen() async throws {
        let store = makeTestStore(assets: []) // nothing to organize → the run fails
        let revealed = expectation(description: "processing screen must not hand over")
        revealed.isInverted = true

        let window = try show(ProcessingView { revealed.fulfill() }, store: store)
        defer { window.isHidden = true }

        await fulfillment(of: [revealed], timeout: 3)
        guard case .failed = store.processing else {
            return XCTFail("Expected a failure state, got \(store.processing)")
        }
        XCTAssertFalse(store.hasStory)
    }

    /// A run that finished while the screen wasn't showing is handed over as soon as the screen
    /// appears — without processing the photos a second time.
    func testRunFinishedBeforeScreenAppearsIsHandedOverWithoutReprocessing() async throws {
        let analyzer = CountingAnalyzer()
        let assets = TestLibrary.assets(count: 40)
        let store = makeTestStore(assets: assets, analyzer: analyzer)
        guard case .finished = await store.process() else {
            return XCTFail("Setup run should succeed")
        }
        XCTAssertEqual(analyzer.callCount, assets.count)

        let revealed = expectation(description: "processing screen hands over to the reveal")
        revealed.assertForOverFulfill = true
        let window = try show(ProcessingView { revealed.fulfill() }, store: store)
        defer { window.isHidden = true }

        await fulfillment(of: [revealed], timeout: 10)
        XCTAssertEqual(analyzer.callCount, assets.count, "The finished result must be shown, not recomputed")
        XCTAssertEqual(store.processing, .idle)
    }

    // MARK: - Helpers

    private func show(_ view: ProcessingView, store: StoryStore) throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "Hosted tests need the app's window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view.environment(store))
        window.makeKeyAndVisible()
        return window
    }
}
