import XCTest

/// The hard paywall with a fake App Store (`-ReliveStoreKit free|premium`), never a live purchase:
/// 1. onboarding builds and reveals the story, then the wall opens, with no way to close it;
/// 2. subscribing opens the app, and a relaunch goes straight in;
/// 3. a partner who joined through an invitation is covered and never sees the wall;
/// 4. the opening plays, and with nothing for sale (agreement not active) the wall stays away.
///
/// Screenshots start with "H".
final class HardPaywallUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWallAfterRevealThenSubscribe() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free", "-ReliveUITestHideMadeForYou"]
        app.launch()
        try completeOnboarding(app)

        // 1. The wall, after the reveal
        let purchase = app.buttons["paywallPurchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 10), "The hard paywall did not appear after the reveal")
        XCTAssertFalse(app.buttons["paywallClose"].exists, "The hard paywall has no close button")
        XCTAssertFalse(app.tabBars.buttons["Create"].exists, "The app stays closed behind the wall")
        XCTAssertTrue(app.staticTexts["Keep your story, together"].exists)
        XCTAssertTrue(app.buttons["paywallRestore"].exists, "Restore is always reachable")
        let hint = app.staticTexts["paywallPartnerHint"]
        for _ in 0..<4 where !hint.isHittable { app.swipeUp() }
        XCTAssertTrue(hint.exists, "The wall tells an invited partner how to get in")
        capture("H01-wall")

        // 2. Subscribing opens the app
        app.swipeDown()
        purchase.tap()
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 15), "Subscribing did not open the app")
        capture("H02-in")
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium", "-ReliveUITestHideMadeForYou"]
        relaunched.launch()
        XCTAssertTrue(relaunched.tabBars.buttons["Create"].waitForExistence(timeout: 30), "A subscriber goes straight in")
        XCTAssertFalse(relaunched.buttons["paywallPurchase"].exists)
    }

    @MainActor
    func testInvitedPartnerIsCovered() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free", "-ReliveUITestHideMadeForYou", "-RelivePartnerFake", "partner"]
        app.launch()
        try completeOnboarding(app)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 15), "The invited partner goes straight in")
        XCTAssertFalse(app.buttons["paywallPurchase"].exists, "No wall for the invited partner")
        capture("H03-partner-in")
    }

    @MainActor
    func testSplashThenNoWallWhenNothingIsForSale() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "empty", "-ReliveUITestHideMadeForYou", "-ReliveUITestSplash"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["splash"].waitForExistence(timeout: 5), "The opening plays")
        capture("H04-splash")
        try completeOnboarding(app)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 15), "Nothing to buy: the app opens")
        XCTAssertFalse(app.buttons["paywallPurchase"].exists)
    }

    // MARK: - Steps

    /// Welcome → name → date → photos → processing → See Our Story.
    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) throws {
        let findStory = app.buttons["Find Our Story"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["paywallPurchase"].exists, "No paywall at launch")
        findStory.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Emma\n")

        XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 5))
        app.buttons["startDateSkip"].tap()
        let manual = app.buttons["startManual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()

        let choose = app.buttons["Choose Our Photos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        allowSystemAlertIfShown()

        let seeStory = app.buttons["See Our Story"]
        var waited = 0
        while !seeStory.waitForExistence(timeout: 30), waited < 330 {
            waited += 30
            allowSystemAlertIfShown()
        }
        XCTAssertTrue(seeStory.exists, "Processing did not finish")
        XCTAssertFalse(app.buttons["paywallPurchase"].exists, "The story is revealed before the wall")
        seeStory.tap()
    }

    @MainActor
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        // Photos access: "Allow Full Access" (iOS may ask to confirm in a second alert).
        let allow = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label == %@", "Full Access", "All Photos", "Allow")
        let button = alert.buttons.matching(allow).firstMatch
        guard button.exists else { return }
        button.tap()
        let confirmation = springboard.alerts.firstMatch
        if confirmation.waitForExistence(timeout: 2) {
            let again = confirmation.buttons.matching(allow).firstMatch
            if again.exists { again.tap() }
        }
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
