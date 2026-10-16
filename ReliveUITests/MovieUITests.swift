import XCTest

/// Memory Movie with the sample library:
/// free: Create → Memory Movie → Choose a Trip → Relive's cut → play → change style and shape →
/// move and remove a scene → Save Video → paywall ("Keep this movie") → close, the edit is as it
/// was → paywall again → close. Relaunch as Premium: the draft is still there → Save Video →
/// progress → saved. The opening title: Try another → the user's own words → still there after
/// the relaunch. Then Made for You → the trip's movie (no paywall), and dark mode and the
/// largest text size for review.
///
/// Screenshots start with "V" (or "W" on an iPhone SE, where CI runs this test again).
final class MovieUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMakeEditKeepAMovie() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        try completeOnboarding(app)
        let prefix = app.windows.firstMatch.frame.height < 700 ? "W" : "V"

        // Made for You: the Kaş trip, offered as a film, opens straight into the editor — no
        // paywall, nothing saved.
        app.tabBars.buttons["Create"].tap()
        let movieCard = app.buttons.matching(identifier: "madeForYouCard").matching(NSPredicate(format: "value == %@", "movie")).firstMatch
        XCTAssertTrue(movieCard.waitForExistence(timeout: 15), "Made for You offers the trip as a movie")
        movieCard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moviePreview"].waitForExistence(timeout: 20), "Made for You did not open the movie")
        XCTAssertFalse(paywall(app).exists, "opening a suggestion never asks for Premium")
        sleep(2)
        capture("\(prefix)09-made-for-you-movie")
        app.buttons["movieClose"].tap()
        sleep(1)

        // Create → Memory Movie → a trip.
        tapClearOfTabBar(app, app.buttons["createMovie"])
        capture("\(prefix)00-movie-sources")
        app.buttons["movieSourceTrip"].tap()
        let trip = app.descendants(matching: .any).matching(identifier: "periodPickerRow").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 10), "No trips listed")
        capture("\(prefix)01-trip-picker")
        trip.tap()

        let preview = app.descendants(matching: .any)["moviePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20), "The movie editor did not open")
        XCTAssertFalse(paywall(app).exists, "making and previewing a movie never asks for Premium")
        sleep(3)
        capture("\(prefix)02-editor")
        printScreen(app, "movie-editor")

        // Preview plays without exporting.
        app.buttons["moviePlay"].tap()
        sleep(2)
        capture("\(prefix)03-playing")
        app.buttons["moviePlay"].tap()

        // Style and shape.
        reveal(app, app.buttons["movieStyle-film"])
        app.buttons["movieStyle-film"].tap()
        sleep(1)
        let wide = app.buttons["16:9 Wide"]
        reveal(app, wide)
        wide.tap()
        sleep(2)
        app.swipeDown()
        sleep(1)
        capture("\(prefix)04-wide-film")
        reveal(app, app.buttons["9:16 Tall"])
        app.buttons["9:16 Tall"].tap()
        sleep(1)

        // Move one scene later, then remove another.
        let summary = app.descendants(matching: .any)["movieSummary"]
        let before = summary.label
        let scenes = app.buttons.matching(identifier: "movieScene")
        reveal(app, scenes.element(boundBy: 1))
        scenes.element(boundBy: 1).tap()
        let later = app.buttons["movieSceneLater"]
        reveal(app, later)
        later.tap()
        sleep(1)
        scenes.element(boundBy: 3).tap()
        let remove = app.buttons["movieSceneRemove"]
        reveal(app, remove)
        remove.tap()
        sleep(1)
        capture("\(prefix)05-scenes-edited")
        let edited = summary.label
        XCTAssertNotEqual(edited, before, "removing a scene changes the movie: \(before) → \(edited)")

        // Words: Relive's title → another safe one → the user's own, which the draft keeps.
        let titleText = app.staticTexts["movieTitleText"]
        let tryAnother = app.buttons["movieTitleTryAnother"]
        reveal(app, tryAnother)
        let reliveTitle = titleText.label
        XCTAssertEqual(tryAnother.label, "Try another title", "VoiceOver says what Try another does")
        tryAnother.tap()
        sleep(1)
        XCTAssertNotEqual(titleText.label, reliveTitle, "Try another shows another title")
        print("EDITORIAL title-variant-changed=\(titleText.label != reliveTitle)")
        capture("\(prefix)10-title-another")
        app.buttons["movieTitleEdit"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Edit title opens a text field")
        // The field holds the current title: put the cursor at its end, then clear it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 4))
        }
        field.typeText("Our favorite trip")
        app.alerts.buttons["Save"].tap()
        sleep(1)
        XCTAssertEqual(titleText.label, "Title: Our favorite trip", "the user's words are kept as written")
        XCTAssertTrue(app.buttons["movieTitleReset"].exists, "the user can go back to Relive's title")
        capture("\(prefix)11-title-own")

        // Keeping it is Premium; closing the paywall returns to the movie exactly as it was.
        app.buttons["movieSave"].tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "Save Video asks for Premium")
        sleep(1)
        capture("\(prefix)06-paywall")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10))
        XCTAssertEqual(summary.label, edited, "the edit is preserved")
        XCTAssertTrue(app.buttons["movieStyle-film"].isSelected, "the style is preserved")
        app.buttons["movieShare"].tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "Share asks for Premium too")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10))
        app.terminate()

        // Premium, after a relaunch: the draft is there, unchanged; it saves.
        let premium = XCUIApplication()
        premium.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"]
        premium.launch()
        XCTAssertTrue(premium.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        premium.tabBars.buttons["Create"].tap()
        let draft = premium.buttons["continueEditing"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10), "The movie draft did not survive the relaunch")
        draft.tap()
        let restoredSummary = premium.descendants(matching: .any)["movieSummary"]
        XCTAssertTrue(restoredSummary.waitForExistence(timeout: 20))
        XCTAssertEqual(restoredSummary.label, edited, "the draft reopens as it was")
        XCTAssertEqual(premium.staticTexts["movieTitleText"].label, "Title: Our favorite trip", "the user's title survives closing and reopening")
        premium.buttons["movieSave"].tap()
        XCTAssertFalse(paywall(premium).waitForExistence(timeout: 2), "Premium saw the paywall")
        let progress = premium.descendants(matching: .any)["movieExportProgress"]
        if progress.waitForExistence(timeout: 5) {
            capture("\(prefix)07-export-progress")
        }
        XCTAssertTrue(waitForExport(premium), "The movie did not save")
        capture("\(prefix)08-saved")
        premium.buttons["movieClose"].tap()
        sleep(1)
        // Exporting that trip's movie made its suggestion: it steps away.
        let retired = premium.buttons.matching(identifier: "madeForYouCard").matching(NSPredicate(format: "value == %@", "movie")).firstMatch
        XCTAssertFalse(retired.waitForExistence(timeout: 3), "a made movie suggestion retires")
        premium.terminate()

        // Review: dark mode and the largest accessibility text size.
        for (name, arguments) in [("dark", ["-ReliveUITestDarkMode"]),
                                  ("large-text", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let review = XCUIApplication()
            review.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"] + arguments
            review.launch()
            XCTAssertTrue(review.tabBars.buttons["Create"].waitForExistence(timeout: 30))
            review.tabBars.buttons["Create"].tap()
            tapClearOfTabBar(review, review.buttons["createMovie"])
            review.buttons["movieSourceTrip"].tap()
            let row = review.descendants(matching: .any).matching(identifier: "periodPickerRow").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            XCTAssertTrue(review.descendants(matching: .any)["moviePreview"].waitForExistence(timeout: 20))
            sleep(3)
            capture("\(prefix)8\(name == "dark" ? "0" : "2")-\(name)-editor")
            review.swipeUp()
            sleep(1)
            capture("\(prefix)8\(name == "dark" ? "1" : "3")-\(name)-controls")
            XCTAssertTrue(review.buttons["movieSave"].isHittable, "Save Video stays reachable (\(name))")
            review.terminate()
        }
    }

    // MARK: - Steps

    private func paywall(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywallClose"]
    }

    @MainActor
    private func waitForExport(_ app: XCUIApplication) -> Bool {
        let finished = app.descendants(matching: .any)["movieExportFinished"]
        let failed = app.descendants(matching: .any)["movieExportFailed"]
        for _ in 0..<180 {
            if finished.exists { return true }
            if failed.exists {
                print("SCREEN movie-export-failed: \(failed.label)")
                return false
            }
            allowSystemAlertIfShown(timeout: 1)
        }
        return finished.exists
    }

    /// Scrolls the editor until `element` is comfortably on screen.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element.identifier) is missing")
        let screen = app.windows.firstMatch.frame
        for _ in 0..<8 where !(element.isHittable && element.frame.maxY < screen.maxY - 150 && element.frame.minY > screen.minY + 90) {
            if element.frame.minY <= screen.minY + 90 { app.swipeDown() } else { app.swipeUp() }
            sleep(1)
        }
    }

    @MainActor
    private func printScreen(_ app: XCUIApplication, _ name: String) {
        let buttons = app.buttons.allElementsBoundByIndex.prefix(50).map { "\($0.identifier)=\($0.label)" }
        print("SCREEN \(name): buttons[\(buttons.joined(separator: " | "))]")
    }

    @MainActor
    private func tapClearOfTabBar(_ app: XCUIApplication, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element.identifier) is missing")
        let screen = app.windows.firstMatch.frame
        let top = screen.minY + 100, bottom = screen.maxY - 110
        func visible() -> ClosedRange<CGFloat>? {
            guard element.exists else { return nil }
            let low = max(element.frame.minY, top), high = min(element.frame.maxY, bottom)
            return high - low >= 30 ? low...high : nil
        }
        for _ in 0..<20 where visible() == nil {
            // Fast while it is far away, slow once it is close: a fast swipe can carry a tall tile
            // right past the band on a small screen.
            let far = element.frame.minY > bottom + screen.height * 0.4 || element.frame.maxY < top - screen.height * 0.4
            let velocity: XCUIGestureVelocity = far ? .fast : .slow
            if element.frame.midY > (top + bottom) / 2 { app.swipeUp(velocity: velocity) } else { app.swipeDown(velocity: velocity) }
            sleep(1)
        }
        guard let band = visible() else {
            printScreen(app, "not-reachable-\(element.identifier)")
            return XCTFail("\(element.identifier) is not reachable")
        }
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: element.frame.midX, dy: (band.lowerBound + band.upperBound) / 2))
            .tap()
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
        // First Experience V2: begin by choosing memories (the picker is replaced by an import
        // of the simulator's library in UI tests).
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
        seeStory.tap()
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 10), "Main app did not appear")
    }

    @MainActor
    private func allowSystemAlertIfShown(timeout: TimeInterval = 3) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        // Photos access: "Allow Full Access" (iOS may ask to confirm in a second alert).
        let allow = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label == %@", "Full Access", "All Photos", "Allow")
        print("SCREEN system-alert: \(alert.label) [\(alert.buttons.allElementsBoundByIndex.map(\.label).joined(separator: " | "))]")
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
