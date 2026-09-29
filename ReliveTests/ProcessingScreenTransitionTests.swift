import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

/// Regression tests for the processing screen getting stuck on "Choosing a few favorites…"
/// after the pipeline had already finished (first real-device test, 53 photos in 2 seconds).
///
/// The real `ProcessingView` is rendered in a window, so SwiftUI's actual update cycle decides
/// what the screen sees — the part of the system where the bug lived.
@MainActor
final class ProcessingScreenTransitionTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// A pipeline that completes within a frame or two must still take the user to the reveal —
    /// exactly once.
    func testFastPipelineLeavesProcessingScreenExactlyOnce() async throws {
        let store = makeStore(assets: TestLibrary.assets(count: 300))
        let revealed = expectation(description: "processing screen hands over to the reveal")
        revealed.assertForOverFulfill = true

        try show(ProcessingView { revealed.fulfill() }, store: store)

        await fulfillment(of: [revealed], timeout: 15)
        XCTAssertTrue(store.hasStory, "The story should have been built and kept")
        XCTAssertEqual(store.processing, .idle, "The finished result should have been acknowledged")

        // Give any late, duplicate hand-over a chance to happen (over-fulfilment fails the test).
        try await Task.sleep(for: .milliseconds(500))
    }

    /// A failed pipeline must never look like success.
    func testFailedPipelineNeverLeavesProcessingScreen() async throws {
        let store = makeStore(assets: []) // nothing to organize → the run fails
        let revealed = expectation(description: "processing screen must not hand over")
        revealed.isInverted = true

        try show(ProcessingView { revealed.fulfill() }, store: store)

        await fulfillment(of: [revealed], timeout: 3)
        guard case .failed = store.processing else {
            return XCTFail("Expected a failure state, got \(store.processing)")
        }
        XCTAssertFalse(store.hasStory)
    }

    // MARK: - Helpers

    private func makeStore(assets: [MemoryAsset]) -> StoryStore {
        StoryStore(
            repository: InMemoryStoryRepository(assets: assets),
            photoLibrary: FakePhotoLibrary(assets: assets),
            analyzer: InstantAnalyzer(),
            placeResolver: GeocodingPlaceResolver(cacheURL: TestLibrary.temporaryPlaceCacheURL()),
            analytics: InMemoryAnalyticsTracker()
        )
    }

    private func show(_ view: ProcessingView, store: StoryStore) throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "Hosted tests need the app's window scene"
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view.environment(store))
        window.makeKeyAndVisible()
        self.window = window
    }
}
