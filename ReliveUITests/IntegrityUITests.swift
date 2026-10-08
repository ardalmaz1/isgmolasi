import XCTest

/// The physical-device follow-ups that a simulator can reproduce:
/// - Favorites "+" adds memories straight from Relive's own library (no system picker);
/// - a collage draft survives the app being killed mid-edit, and resumes as it was;
/// - favorites survive that relaunch.
///
/// Starts fresh and goes through onboarding first. Screenshots start with "I".
final class IntegrityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFavoritesPlusAndDraftAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "premium"]
        app.launch()
        try completeOnboarding(app)

        // Favorites → + : choose two memories from Relive's own library
        app.tabBars.buttons["Us"].tap()
        let usFavorites = app.buttons["usFavorites"]
        XCTAssertTrue(usFavorites.waitForExistence(timeout: 10))
        usFavorites.tap()
        let addFromEmpty = app.buttons["Add Favorites"].firstMatch
        XCTAssertTrue(addFromEmpty.waitForExistence(timeout: 10), "The empty Favorites screen offers no way to add")
        capture("I01-favorites-empty")
        addFromEmpty.tap()
        let cells = app.buttons.matching(identifier: "addFavoritePhoto")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "No memories to add")
        sleep(1)
        let hittable = cells.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(hittable.count, 2)
        hittable[0].tap()
        hittable[1].tap()
        XCTAssertEqual(hittable[0].value as? String, "Selected")
        capture("I02-add-favorites")
        let confirm = app.buttons["addFavoritesConfirm"]
        XCTAssertTrue(confirm.isEnabled)
        print("SCREEN add-confirm: \(confirm.label)")
        confirm.tap()
        let favorites = app.buttons.matching(identifier: "favoritePhoto")
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 10), "The added favorites don't show")
        XCTAssertEqual(favorites.count, 2)
        capture("I03-favorites-added")
        // Adding again doesn't duplicate: they show as already favorites.
        app.buttons["addFavorites"].tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        let already = cells.allElementsBoundByIndex.filter { ($0.value as? String) == "Already a favorite" }
        XCTAssertEqual(already.count, 2, "favorites are marked, not offered twice")
        app.buttons["Cancel"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        // A collage draft: one change, then the app is killed mid-edit
        app.tabBars.buttons["Create"].tap()
        let collageFromMoment = app.buttons["createCollageMoment"]
        XCTAssertTrue(collageFromMoment.waitForExistence(timeout: 10))
        tapClearOfTabBar(app, collageFromMoment)
        try pickFirstMoment(app)
        let preview = app.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Collage editor did not open")
        sleep(2)
        let newStyle = preview.label.contains("Film") ? "Grid" : "Film"
        tapScrollingIntoView(app, app.buttons[newStyle].firstMatch)
        sleep(1)
        let draftLabel = preview.label
        print("SCREEN draft-collage: \(draftLabel)")
        XCTAssertTrue(draftLabel.contains(newStyle))
        app.terminate()

        // Relaunch: the draft is there and resumes as it was; favorites are still there
        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"]
        relaunched.launch()
        XCTAssertTrue(relaunched.tabBars.buttons["Create"].waitForExistence(timeout: 30), "Main app did not appear after relaunch")
        relaunched.tabBars.buttons["Create"].tap()
        let continueEditing = relaunched.buttons["continueEditing"]
        XCTAssertTrue(continueEditing.waitForExistence(timeout: 10), "The draft did not survive the app being closed")
        capture("I04-draft-after-relaunch")
        continueEditing.tap()
        let resumed = relaunched.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(resumed.waitForExistence(timeout: 10))
        XCTAssertEqual(resumed.label, draftLabel, "The draft did not resume as it was")
        relaunched.buttons["Close"].firstMatch.tap()

        relaunched.tabBars.buttons["Us"].tap()
        let favoritesRow = relaunched.buttons["usFavorites"]
        XCTAssertTrue(favoritesRow.waitForExistence(timeout: 10))
        favoritesRow.tap()
        let kept = relaunched.buttons.matching(identifier: "favoritePhoto")
        XCTAssertTrue(kept.firstMatch.waitForExistence(timeout: 10), "Favorites did not survive the relaunch")
        XCTAssertEqual(kept.count, 2)
        capture("I05-favorites-after-relaunch")
    }

    // MARK: - Steps

    /// Taps a control on Create once it is clear of the tab bar (a tap under it switches tabs).
    @MainActor
    private func tapClearOfTabBar(_ app: XCUIApplication, _ element: XCUIElement) {
        let screen = app.windows.firstMatch.frame
        func isClear() -> Bool {
            element.isHittable && element.frame.minY > screen.minY + 80 && element.frame.maxY < screen.maxY - 90
        }
        for _ in 0..<8 where !isClear() {
            if element.frame.minY <= screen.minY + 80 { app.swipeDown() } else { app.swipeUp() }
            sleep(1)
        }
        XCTAssertTrue(isClear(), "\(element.identifier) is not reachable")
        element.tap()
    }

    /// Scrolls an editor control clear of the save bar and the navigation bar, taps it, and
    /// scrolls back.
    @MainActor
    private func tapScrollingIntoView(_ app: XCUIApplication, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        func isClear() -> Bool {
            element.isHittable && element.frame.minY > screen.minY + 110 && element.frame.maxY < screen.maxY - 200
        }
        var scrolled = 0
        while !isClear(), scrolled < 4 {
            app.swipeUp()
            sleep(1)
            scrolled += 1
        }
        XCTAssertTrue(isClear(), "\(element.label) is not reachable")
        element.tap()
        for _ in 0..<scrolled { app.swipeDown() }
    }

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
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isEnabled && $0.isHittable }, "No moment with enough photos")
        row.tap()
    }

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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
