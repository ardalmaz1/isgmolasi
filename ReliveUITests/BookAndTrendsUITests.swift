import XCTest

/// Walks the v0.3 flows against the simulator's sample library:
/// Trending Now → a local trend (detail, Choose Photos, studio, another variation, Save to Photos)
/// → the AI trend (disclosure shown, nothing to start) → Memory Book from a trip (cover, pages,
/// Save Page, Edit style) → the book is still there after relaunching.
///
/// Starts fresh and goes through onboarding first, so it doesn't depend on test order.
/// Screenshots are attached to the test result (names starting with "T" and "B").
final class BookAndTrendsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTrendsAndMemoryBook() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh"]
        app.launch()
        try completeOnboarding(app)

        // Create: Trending Now first
        app.tabBars.buttons["Create"].tap()
        let firstTrend = app.buttons["trendCard-bw-editorial"]
        XCTAssertTrue(firstTrend.waitForExistence(timeout: 10), "Trending Now is missing")
        sleep(3)
        capture("T01-create-trending")
        printScreen(app, "create-trending")

        // A local trend, start to finish
        firstTrend.tap()
        let choose = app.buttons["trendChoosePhotos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "Trend detail did not open")
        XCTAssertFalse(app.descendants(matching: .any)["aiDisclosure"].exists, "On-device trends show no AI disclosure")
        sleep(2)
        capture("T02-trend-detail")
        printScreen(app, "trend-detail")
        choose.tap()

        try choosePhotos(app, count: 2)
        let preview = app.descendants(matching: .any)["trendPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Trend studio did not open")
        sleep(3)
        capture("T03-trend-studio")
        app.buttons["Soft"].firstMatch.tap()
        sleep(3)
        capture("T04-trend-variation")
        XCTAssertTrue(preview.label.contains("Soft"), "The preview did not switch variation")

        let save = app.buttons["trendSave"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "Trend creation was not saved")
        capture("T05-trend-saved")
        XCTAssertFalse(save.isEnabled, "An unchanged creation can't be saved twice")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        sleep(1)
        app.navigationBars.buttons.firstMatch.tap()

        // The AI trend: honest about not being available, and about what it would need
        let aiCard = app.buttons["trendCard-golden-hour-portrait"]
        let row = app.scrollViews["trendingRow"]
        for _ in 0..<6 where !(aiCard.exists && aiCard.isHittable) {
            row.swipeLeft()
            sleep(1)
        }
        XCTAssertTrue(aiCard.isHittable, "The AI trend card is not reachable")
        XCTAssertTrue(aiCard.label.contains("Coming soon"), "The AI trend is not marked as coming soon")
        aiCard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["aiDisclosure"].waitForExistence(timeout: 10), "AI disclosure missing")
        let unavailable = app.buttons["trendUnavailable"]
        XCTAssertTrue(unavailable.exists)
        XCTAssertFalse(unavailable.isEnabled, "An AI trend can't be started without a provider")
        XCTAssertFalse(app.buttons["trendChoosePhotos"].exists)
        app.swipeUp()
        sleep(1)
        capture("T06-ai-trend")
        printScreen(app, "ai-trend")
        app.navigationBars.buttons.firstMatch.tap()

        // Memory Book from a trip
        let startBook = app.buttons["createBook"]
        XCTAssertTrue(startBook.waitForExistence(timeout: 10))
        startBook.tap()
        let fromTrip = app.buttons["A Trip"]
        XCTAssertTrue(fromTrip.waitForExistence(timeout: 5), "No trips to make a book from")
        capture("B01-book-sources")
        fromTrip.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "periodPickerRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No trips listed")
        sleep(1)
        capture("B02-trips")
        let trip = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isEnabled && $0.isHittable }, "No trip with enough photos")
        trip.tap()

        let pages = app.descendants(matching: .any)["bookPages"]
        let pageLabel = app.staticTexts["bookPageLabel"]
        XCTAssertTrue(pages.waitForExistence(timeout: 10), "The book did not open")
        sleep(3)
        capture("B03-book-cover")
        printScreen(app, "book-cover")
        XCTAssertEqual(pageLabel.label, "Cover")

        pages.swipeLeft()
        sleep(2)
        capture("B04-book-page-2")
        XCTAssertTrue(pageLabel.label.hasPrefix("Page 2 of"), "Swiping did not turn the page: \(pageLabel.label)")
        pages.swipeLeft()
        sleep(1)
        pages.swipeLeft()
        sleep(2)
        capture("B05-book-page-4")
        printScreen(app, "book-page")

        let savePage = app.buttons["bookSavePage"]
        savePage.tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "The page was not saved")
        XCTAssertFalse(savePage.isEnabled, "An unchanged page can't be saved twice")

        app.buttons["bookEdit"].tap()
        XCTAssertTrue(app.buttons["bookEditDone"].waitForExistence(timeout: 10), "Book editor did not open")
        sleep(1)
        capture("B06-book-edit")
        printScreen(app, "book-edit")
        app.buttons["Film"].firstMatch.tap()
        sleep(1)
        app.buttons["bookEditDone"].tap()
        sleep(3)
        capture("B07-book-film")
        XCTAssertTrue(savePage.isEnabled, "A changed book can be saved again")
        app.buttons["Close"].firstMatch.tap()

        let shelf = app.buttons["savedBook"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 10), "The book is not on the shelf")
        XCTAssertTrue(shelf.label.contains("Film"), "The style change was not kept: \(shelf.label)")

        // Reopen the app: the book is still there, and opens
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["-ReliveUITestImportAllPhotos"]
        relaunched.launch()
        XCTAssertTrue(relaunched.tabBars.buttons["Create"].waitForExistence(timeout: 30), "Main app did not appear after relaunch")
        relaunched.tabBars.buttons["Create"].tap()
        let saved = relaunched.buttons["savedBook"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "The book did not survive a relaunch")
        saved.tap()
        XCTAssertTrue(relaunched.descendants(matching: .any)["bookPages"].waitForExistence(timeout: 10), "The saved book did not open")
        sleep(3)
        capture("B08-book-reopened")
        printScreen(relaunched, "book-reopened")
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

    /// Picks the first `count` photos on screen and confirms.
    @MainActor
    private func choosePhotos(_ app: XCUIApplication, count: Int) throws {
        let photos = app.buttons.matching(identifier: "pickerPhoto")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10), "Photo picker did not open")
        sleep(1)
        let visible = photos.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visible.count, count, "Not enough photos to choose from")
        for photo in visible.prefix(count) {
            photo.tap()
        }
        capture("T-picker")
        let done = app.buttons["pickerDone"]
        XCTAssertTrue(done.isEnabled, "Done is not enabled after choosing \(count) photos")
        done.tap()
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
