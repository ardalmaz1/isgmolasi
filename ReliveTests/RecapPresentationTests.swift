import ReliveCore
import SwiftUI
import UIKit
import XCTest
@testable import Relive

/// The immersive recap is really presented over the main tabs (not just requested), in a real
/// window — and so is a creation, the control.
@MainActor
final class RecapPresentationTests: XCTestCase {
    private func host() throws -> (UIWindow, UIViewController, AppModel) {
        let (store, repository) = CreationTestLibrary.makeStore()
        let app = AppModel(storyStore: store, repository: repository, analytics: InMemoryAnalyticsTracker())
        let defaults = PremiumTestKit.defaults()
        let root = MainTabView()
            .environment(app)
            .environment(store)
            .environment(TrendCatalogStore(remote: nil))
            .environment(PremiumTestKit.store(defaults: defaults))
            .environment(MadeForYouStore(defaults: defaults, now: { CreationTestLibrary.now }))
            .environment(\.analytics, InMemoryAnalyticsTracker())
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "Hosted tests need the app's window scene"
        )
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: root)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return (window, controller, app)
    }

    private func waitForPresentation(on controller: UIViewController, _ presented: Bool, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while (controller.presentedViewController != nil) != presented, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func testARecapIsPresentedAndClosesAgain() async throws {
        let (window, controller, app) = try host()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))

        app.openRecap(.year(2025), origin: "test")
        await waitForPresentation(on: controller, true)
        XCTAssertNotNil(controller.presentedViewController, "the recap was requested but not presented")

        app.activeRecap = nil
        await waitForPresentation(on: controller, false)
        XCTAssertNil(controller.presentedViewController)
    }

    func testACreationIsPresented() async throws {
        let (window, controller, app) = try host()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))

        app.startCreation(.collage, from: .choosePhotos, origin: "test")
        await waitForPresentation(on: controller, true)
        XCTAssertNotNil(controller.presentedViewController, "the creation was requested but not presented")
        app.activeCreation = nil
        await waitForPresentation(on: controller, false)
    }
}
