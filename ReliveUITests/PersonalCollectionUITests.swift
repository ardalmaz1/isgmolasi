import XCTest

/// Walks the v0.4 personal collection against the simulator's sample library:
/// favorite photos and a moment → Create from Favorites (collage) → save it to My Creations →
/// reopen, edit, close, reopen → a story draft that is closed and continued → deleting a
/// creation leaves its memories → every Create tool still opens.
///
/// Starts fresh and goes through onboarding first, so it doesn't depend on test order.
/// Screenshots are attached to the test result (names starting with "P").
final class PersonalCollectionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFavoritesCreationsAndDrafts() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh"]
        app.launch()
        try completeOnboarding(app)

        // 1. Favorites: a moment, and two of its photos (separately)
        app.tabBars.buttons["Story"].tap()
        try openVisibleMoment(app)
        let momentHeart = app.buttons["momentFavorite"]
        XCTAssertTrue(momentHeart.waitForExistence(timeout: 10), "The moment has no favorite button")
        XCTAssertEqual(momentHeart.value as? String, "Not selected")
        momentHeart.tap()
        XCTAssertEqual(momentHeart.value as? String, "Selected", "VoiceOver hears 'Favorite moment, Selected'")

        let photos = app.buttons.matching(identifier: "momentPhoto")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<5 where !photos.firstMatch.isHittable {
            app.swipeUp()
            sleep(1)
        }
        photos.firstMatch.tap()
        let photoHeart = app.buttons["photoFavorite"]
        XCTAssertTrue(photoHeart.waitForExistence(timeout: 10), "The photo viewer has no favorite button")
        XCTAssertEqual(photoHeart.value as? String, "Not selected", "favoriting a moment doesn't favorite its photos")
        photoHeart.tap()
        XCTAssertEqual(photoHeart.value as? String, "Selected")
        app.swipeLeft()
        sleep(2)
        XCTAssertEqual(photoHeart.value as? String, "Not selected", "the next photo is not a favorite yet")
        photoHeart.tap()
        sleep(1)
        capture("P01-photo-favorite")
        app.buttons["Close"].firstMatch.tap()
        sleep(1)

        // Create from Favorites → a collage of exactly those photos
        app.tabBars.buttons["Create"].tap()
        let favoritesCount = app.staticTexts["favoritesCount"]
        XCTAssertTrue(favoritesCount.waitForExistence(timeout: 10), "Favorites are not on Create")
        print("SCREEN favorites-count: \(favoritesCount.label)")
        XCTAssertEqual(favoritesCount.label, "You have 3 favorites.", "two photos and a moment")
        sleep(2)
        capture("P02-create-favorites")
        printScreen(app, "create-with-favorites")
        openMenu(app.buttons["createFromFavorites"])
        let collageChoice = app.buttons["Memory Collage"]
        XCTAssertTrue(collageChoice.waitForExistence(timeout: 5), "Create from Favorites has no collage")
        collageChoice.tap()
        let preview = app.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The collage from favorites did not open")
        sleep(3)
        print("SCREEN favorites-collage: \(preview.label)")
        XCTAssertTrue(preview.label.hasSuffix("2 photos"), "The collage is not made of the two favorite photos: \(preview.label)")
        capture("P03-collage-from-favorites")

        // 3. Save it to My Creations; the toolbar then offers the heart
        app.buttons["creationKeep"].tap()
        let creationHeart = app.buttons["creationFavorite"]
        XCTAssertTrue(creationHeart.waitForExistence(timeout: 5), "Saving didn't move it to My Creations")
        creationHeart.tap()
        XCTAssertEqual(creationHeart.value as? String, "Selected")
        let savedLabel = preview.label
        app.buttons["Close"].firstMatch.tap()

        let savedCollage = app.buttons["savedCollage"]
        XCTAssertTrue(savedCollage.waitForExistence(timeout: 10), "The collage is not in Your Creations")
        print("SCREEN saved-collage: \(savedCollage.label)")
        XCTAssertTrue(savedCollage.label.contains("Favorite"), "Its favorite state isn't announced: \(savedCollage.label)")
        sleep(2)
        capture("P04-your-creations")

        // Reopen: the same collage, then an edit that survives closing
        savedCollage.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The saved collage did not reopen")
        XCTAssertEqual(preview.label, savedLabel, "The collage did not reopen as it was")
        let newStyle = savedLabel.contains("Film") ? "Grid" : "Film"
        app.buttons[newStyle].firstMatch.tap()
        sleep(1)
        let editedLabel = preview.label
        XCTAssertTrue(editedLabel.contains(newStyle))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(savedCollage.waitForExistence(timeout: 10))
        savedCollage.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.label, editedLabel, "The edit was not kept")
        capture("P05-collage-reopened")
        app.buttons["Close"].firstMatch.tap()

        // 2. A story draft: change the style, correct a card, close, continue
        let storyFromMoment = app.buttons["createStoryMoment"]
        XCTAssertTrue(storyFromMoment.waitForExistence(timeout: 10))
        storyFromMoment.tap()
        try pickFirstMoment(app)
        let cards = app.descendants(matching: .any)["storyCards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "Story Maker did not open")
        sleep(3)
        let editorial = app.buttons["Editorial"].firstMatch
        let storyStyle = editorial.isSelected ? "Film" : "Editorial"
        app.buttons[storyStyle].firstMatch.tap()
        sleep(1)
        openMenu(app.buttons["storyEditCard"])
        let hideDate = app.buttons["Hide Date"]
        if hideDate.waitForExistence(timeout: 3) {
            hideDate.tap()
        } else {
            app.tap()
        }
        sleep(2)
        let openingBefore = openingCardLabel(app)
        print("SCREEN draft-opening: \(openingBefore)")
        capture("P06-story-draft")
        app.buttons["Close"].firstMatch.tap()

        let continueEditing = app.buttons["continueEditing"]
        XCTAssertTrue(continueEditing.waitForExistence(timeout: 10), "No Continue Editing after closing a changed story")
        printScreen(app, "continue-editing")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Story · Edited")).firstMatch.exists, "The draft doesn't say what it is and when it was edited")
        sleep(1)
        capture("P07-continue-editing")
        continueEditing.tap()
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "The draft did not reopen")
        sleep(2)
        XCTAssertTrue(app.buttons[storyStyle].firstMatch.isSelected, "The style was not kept")
        XCTAssertEqual(openingCardLabel(app), openingBefore, "The card corrections were not kept")
        capture("P08-story-resumed")
        app.buttons["Close"].firstMatch.tap()

        // 4. Deleting a creation leaves its memories
        app.tabBars.buttons["Us"].tap()
        let memoriesStat = app.staticTexts["stat-Memories"]
        let memoriesBefore = memoriesStat.waitForExistence(timeout: 5) ? memoriesStat.label : nil
        print("SCREEN memories-before: \(memoriesBefore ?? "?")")
        app.tabBars.buttons["Create"].tap()
        let seeAll = app.buttons["seeAllCreations"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 10))
        seeAll.tap()
        XCTAssertTrue(savedCollage.waitForExistence(timeout: 10), "My Creations doesn't list the collage")
        sleep(1)
        capture("P09-my-creations")
        savedCollage.press(forDuration: 1.2)
        let delete = app.buttons["Delete Collage"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "No Delete in the creation's menu")
        delete.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Delete this collage?"].waitForExistence(timeout: 5), "Delete was not confirmed first")
        let confirm = app.buttons["Delete Collage"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("P10-delete-confirmation")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["creationsEmpty"].waitForExistence(timeout: 10), "The collage was not deleted")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Us"].tap()
        if let memoriesBefore {
            XCTAssertTrue(memoriesStat.waitForExistence(timeout: 5))
            XCTAssertEqual(memoriesStat.label, memoriesBefore, "Deleting a creation changed the memories")
        }
        let usFavorites = app.buttons["usFavorites"]
        XCTAssertTrue(usFavorites.waitForExistence(timeout: 5), "Favorites can't be reached from Us")
        usFavorites.tap()
        let favoritePhotos = app.buttons.matching(identifier: "favoritePhoto")
        XCTAssertTrue(favoritePhotos.firstMatch.waitForExistence(timeout: 10), "The favorite photos are gone")
        XCTAssertEqual(favoritePhotos.count, 2, "The collage's photos are still there, still favorites")
        sleep(1)
        capture("P11-favorites")
        printScreen(app, "favorites")
        app.navigationBars.buttons.firstMatch.tap()

        // 5. Every Create tool still opens
        app.tabBars.buttons["Create"].tap()
        tapTool(app, "createCollagePhotos")
        XCTAssertTrue(app.buttons["sourceRelive"].waitForExistence(timeout: 10), "Memory Collage did not open")
        app.buttons["Cancel"].firstMatch.tap()

        tapTool(app, "createStoryMoment")
        XCTAssertTrue(app.buttons.matching(identifier: "momentPickerRow").firstMatch.waitForExistence(timeout: 10), "Story Maker did not open")
        app.buttons["Cancel"].firstMatch.tap()

        tapTool(app, "createBook")
        XCTAssertTrue(app.buttons["A Moment"].waitForExistence(timeout: 5), "Memory Book did not open")
        app.buttons["Cancel"].firstMatch.tap()

        tapTool(app, "createMonthlyRecap")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "recapMonthRow").firstMatch.waitForExistence(timeout: 10), "Monthly Recap did not open")
        app.navigationBars.buttons.firstMatch.tap()

        tapTool(app, "createOurYear")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10), "Our Year did not open")
        sleep(2)
        capture("P12-our-year")
        printScreen(app, "our-year")
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - Steps

    @MainActor
    private func tapTool(_ app: XCUIApplication, _ identifier: String) {
        let tool = app.buttons[identifier]
        XCTAssertTrue(tool.waitForExistence(timeout: 10), "\(identifier) is missing")
        for _ in 0..<6 where !tool.isHittable {
            app.swipeUp()
            sleep(1)
        }
        tool.tap()
    }

    @MainActor
    private func openingCardLabel(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Opening card")).firstMatch.label
    }

    /// Opens a moment whose card is fully on screen (one peeking under the status bar would
    /// send the tap to the status bar).
    @MainActor
    private func openVisibleMoment(_ app: XCUIApplication) throws {
        let cards = app.buttons.matching(identifier: "momentCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "No moments in the timeline")
        sleep(2)
        let screen = app.windows.firstMatch.frame
        let visible = cards.allElementsBoundByIndex.first { card in
            card.isHittable && card.frame.midY > screen.minY + 120 && card.frame.midY < screen.maxY - 140
        } ?? cards.allElementsBoundByIndex.first { $0.isHittable }
        try XCTUnwrap(visible, "No tappable moment card").tap()
    }

    /// Opens a SwiftUI menu by tapping its centre.
    @MainActor
    private func openMenu(_ menu: XCUIElement) {
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
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
