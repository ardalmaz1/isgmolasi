import XCTest

/// Walks the v0.3.1 flows against the simulator's sample library:
/// Story Maker (Relive's design → Make it for me → Edit Card → Save All) → a collage from the
/// Photo Library source → Our Year for a year that isn't one yet.
///
/// The photo library "picker" is replaced by a debug stand-in (`-ReliveUITestPhotoLibraryPicks`)
/// because Apple's picker runs out of process; everything after the pick is real.
/// Screenshots are attached to the test result (names starting with "S", "L" and "Y").
final class StoryAndSourcesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStoryMakerPhotoLibraryAndOurYear() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveUITestPhotoLibraryPicks"]
        app.launch()
        try completeOnboarding(app)
        app.tabBars.buttons["Create"].tap()

        // Story Maker: Relive designs the story
        let storyFromMoment = app.buttons["createStoryMoment"]
        XCTAssertTrue(storyFromMoment.waitForExistence(timeout: 10))
        storyFromMoment.tap()
        try pickFirstMoment(app)
        let cards = app.descendants(matching: .any)["storyCards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "Story Maker did not open")
        sleep(3)
        capture("S01-story-designed")
        printScreen(app, "story-designed")
        let firstLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Opening card")).firstMatch.label
        print("SCREEN story-opening: \(firstLabel)")

        app.buttons["storyMakeItForMe"].tap()
        sleep(3)
        capture("S02-story-make-it-for-me")

        // Small corrections to a card
        cards.swipeLeft()
        sleep(2)
        openMenu(app.buttons["storyEditCard"])
        let changeLayout = app.buttons["Change Layout"]
        XCTAssertTrue(changeLayout.waitForExistence(timeout: 5), "Edit Card has no Change Layout")
        changeLayout.tap()
        sleep(2)
        capture("S03-story-change-layout")

        openMenu(app.buttons["storyEditCard"])
        let hideDate = app.buttons["Hide Date"]
        if hideDate.waitForExistence(timeout: 3) {
            hideDate.tap()
        } else {
            app.tap() // dismiss the menu
        }
        sleep(2)
        capture("S04-story-edited")

        let saveAll = app.buttons["storySaveAll"]
        XCTAssertTrue(saveAll.waitForExistence(timeout: 5))
        print("SCREEN story-save-all: \(saveAll.label)")
        saveAll.tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "Story cards were not saved")
        capture("S05-story-saved")
        app.buttons["Close"].firstMatch.tap()

        // A collage from the photo library
        let collagePhotos = app.buttons["createCollagePhotos"]
        XCTAssertTrue(collagePhotos.waitForExistence(timeout: 10))
        collagePhotos.tap()
        let fromLibrary = app.buttons["sourcePhotoLibrary"]
        XCTAssertTrue(fromLibrary.waitForExistence(timeout: 10), "No photo source choice")
        XCTAssertTrue(app.buttons["sourceRelive"].exists)
        capture("L01-photo-source")
        fromLibrary.tap()
        let preview = app.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "The collage from the photo library did not open")
        sleep(3)
        capture("L02-collage-from-library")
        printScreen(app, "collage-from-library")
        app.buttons["Close"].firstMatch.tap()

        // Our Year for a year that isn't one yet
        let ourYear = app.buttons["createOurYear"]
        XCTAssertTrue(ourYear.waitForExistence(timeout: 10))
        ourYear.tap()
        sleep(2)
        printScreen(app, "years")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Our 2025")).firstMatch.exists, "a full year is listed as Our 2025")
        let notYet = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{4}.*")).firstMatch
        XCTAssertTrue(notYet.waitForExistence(timeout: 5), "no year that is still getting started")
        print("SCREEN year-row: \(notYet.label)")
        notYet.tap()
        XCTAssertTrue(app.descendants(matching: .any)["yearNotYet"].waitForExistence(timeout: 10), "The honest state is missing")
        XCTAssertTrue(app.buttons["yearBuildFromLibrary"].exists)
        XCTAssertTrue(app.buttons["yearAddMemories"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "And that’s our")).firstMatch.exists)
        sleep(1)
        capture("Y01-year-not-yet")
        printScreen(app, "year-not-yet")
    }

    // MARK: - Steps

    /// Opens a SwiftUI menu by tapping its centre (menus inside a paging view can report
    /// themselves as not hittable to XCTest even when fully visible).
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
