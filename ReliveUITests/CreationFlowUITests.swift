import XCTest

/// Walks the v0.2 creation flows against the simulator's sample library:
/// Create → Memory Collage (from a moment, Make it for me, style, shape, Save to Photos) →
/// Story Maker (from a moment, Save This Card) → Monthly Recap → Our Year → Create from this.
///
/// Starts fresh and goes through onboarding first, so it doesn't depend on test order.
/// Screenshots are attached to the test result (names starting with "C").
final class CreationFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreationFlows() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh"]
        app.launch()
        try completeOnboarding(app)

        // Create home
        app.tabBars.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Memory Collage"].waitForExistence(timeout: 10))
        sleep(2)
        capture("C01-create")
        printScreen(app, "create")

        // Memory Collage from a moment
        app.buttons["createCollageMoment"].tap()
        try pickFirstMoment(app)
        let preview = app.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Collage editor did not open")
        sleep(3)
        capture("C02-collage")
        printScreen(app, "collage")

        app.buttons["makeItForMe"].tap()
        sleep(2)
        capture("C03-collage-make-it-for-me")

        app.buttons["Film"].firstMatch.tap()
        sleep(2)
        capture("C04-collage-film")

        app.buttons["9:16"].firstMatch.tap()
        app.buttons["Film"].firstMatch.swipeLeft()
        sleep(1)
        app.buttons["Polaroid"].firstMatch.tap()
        sleep(2)
        capture("C05-collage-polaroid-story")

        app.buttons["collageSave"].tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "Collage was not saved")
        capture("C06-collage-saved")
        printScreen(app, "collage-saved")
        app.buttons["Close"].firstMatch.tap()

        // Story Maker from a moment
        XCTAssertTrue(app.buttons["createStoryMoment"].waitForExistence(timeout: 10))
        app.buttons["createStoryMoment"].tap()
        try pickFirstMoment(app)
        let cards = app.descendants(matching: .any)["storyCards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "Story Maker did not open")
        sleep(3)
        capture("C07-story-opening")
        printScreen(app, "story")
        cards.swipeLeft()
        sleep(2)
        capture("C08-story-second")
        app.buttons["Editorial"].firstMatch.tap()
        sleep(2)
        capture("C09-story-editorial")
        app.buttons["storySaveOne"].tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "Story card was not saved")
        app.buttons["Close"].firstMatch.tap()

        // Monthly Recap
        XCTAssertTrue(app.buttons["createMonthlyRecap"].waitForExistence(timeout: 10))
        app.buttons["createMonthlyRecap"].tap()
        let month = app.descendants(matching: .any).matching(identifier: "recapMonthRow").firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 10), "No months listed")
        capture("C10-months")
        month.tap()
        sleep(3)
        capture("C11-month")
        printScreen(app, "month")
        app.swipeUp()
        sleep(1)
        capture("C12-month-scrolled")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // Our Year
        XCTAssertTrue(app.buttons["createOurYear"].waitForExistence(timeout: 10))
        app.buttons["createOurYear"].tap()
        sleep(2)
        let yearRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Our 2025")).firstMatch
        if yearRow.waitForExistence(timeout: 3) {
            yearRow.tap()
            sleep(2)
        }
        capture("C13-our-year")
        printScreen(app, "year")
        app.swipeUp()
        sleep(1)
        capture("C14-our-year-scrolled")

        // Create from this, on a moment
        app.tabBars.buttons["Story"].tap()
        let momentCard = app.buttons.matching(identifier: "momentCard").firstMatch
        XCTAssertTrue(momentCard.waitForExistence(timeout: 10))
        momentCard.tap()
        let fromThis = app.buttons["createFromThisCollage"]
        XCTAssertTrue(fromThis.waitForExistence(timeout: 10))
        if !fromThis.isHittable { app.swipeUp() }
        capture("C15-create-from-this")
        fromThis.tap()
        // A one-photo moment (the simulator's own sample photos) can't make a collage on its own:
        // Relive says so and offers to choose more photos instead.
        let notEnough = app.staticTexts["Not enough photos"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10) || notEnough.exists, "Create from this did not open")
        sleep(2)
        capture("C16-create-from-this-opened")
        printScreen(app, "create-from-this")
        if notEnough.exists {
            app.buttons["Choose Photos"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["pickerStatus"].waitForExistence(timeout: 10), "Photo picker did not open")
            capture("C17-choose-more-photos")
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            app.buttons["Close"].firstMatch.tap()
        }
    }

    // MARK: - Steps

    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) throws {
        let findStory = app.buttons["Find Our Story"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        findStory.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Emma\n")

        XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()

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
        seeStory.tap()
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 10), "Main app did not appear")
    }

    @MainActor
    private func pickFirstMoment(_ app: XCUIApplication) throws {
        let rows = app.buttons.matching(identifier: "momentPickerRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No moments to choose from")
        sleep(1)
        capture("C-picker-\(Int(Date().timeIntervalSince1970) % 1000)")
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isEnabled && $0.isHittable }, "No moment with enough photos")
        row.tap()
    }

    /// Waits for an export to finish; prints the failure message if it failed instead.
    @MainActor
    private func waitForExport(_ app: XCUIApplication) -> Bool {
        let finished = app.descendants(matching: .any)["exportFinished"]
        let failed = app.descendants(matching: .any)["exportFailed"]
        for _ in 0..<60 {
            if finished.exists { return true }
            if failed.exists {
                print("SCREEN export-failed: \(failed.label)")
                return false
            }
            allowSystemAlertIfShown()
            sleep(1)
        }
        return finished.exists
    }

    /// Photo access is granted before the run; if iOS still asks (e.g. to add photos), allow it.
    @MainActor
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        print("SCREEN system-alert: \(alert.label)")
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
    }

    @MainActor
    private func printScreen(_ app: XCUIApplication, _ screen: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        print("SCREEN \(screen): \(texts.joined(separator: " | "))")
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
