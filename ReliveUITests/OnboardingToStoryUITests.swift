import XCTest

/// Walks the whole Prototype 0.1 flow against the simulator's photo library:
/// onboarding → processing → reveal → timeline → moment → note → Today → Us.
///
/// Expects the library to contain the generated sample photos (`scripts/make_sample_library.py`)
/// and photo access to be granted beforehand (`xcrun simctl privacy <device> grant photos …`).
/// Screenshots are attached to the test result for review.
final class OnboardingToStoryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFullStoryFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos"]
        app.launch()

        // Welcome
        let findStory = app.buttons["Find Our Story"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        snapshot("01-welcome")
        findStory.tap()

        // Partner
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Emma")
        snapshot("02-partner")
        // Submit with the keyboard's return key ("continue"), which also saves the name.
        nameField.typeText("\n")

        // Start date (keep the default estimate)
        XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 5))
        snapshot("03-start-date")
        app.buttons["Continue"].tap()

        // Photos
        let choose = app.buttons["Choose Our Photos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        snapshot("04-photos")
        choose.tap()
        allowPhotoAccessIfAsked()

        // Processing runs on device; give Vision and geocoding time.
        sleep(4)
        snapshot("05-processing")
        let seeStory = app.buttons["See Our Story"]
        XCTAssertTrue(seeStory.waitForExistence(timeout: 240), "Processing did not finish")
        sleep(3) // let the statistics finish appearing
        snapshot("06-reveal")
        describe(app, "reveal")
        seeStory.tap()

        // Timeline
        let cards = app.buttons.matching(identifier: "momentCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "No moments in the timeline")
        sleep(2)
        snapshot("07-timeline-top")
        logMoments(in: app)
        describe(app, "timeline")
        app.swipeUp()
        sleep(1)
        snapshot("08-timeline-scrolled")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        snapshot("09-timeline-later")

        // Moment detail
        let visibleCard = cards.allElementsBoundByIndex.first { $0.isHittable }
        let card = try XCTUnwrap(visibleCard, "No tappable moment card")
        card.tap()
        let notePrompt = app.buttons["What do you remember about this?"]
        XCTAssertTrue(notePrompt.waitForExistence(timeout: 10))
        sleep(2)
        snapshot("10-moment-detail")
        describe(app, "moment")
        app.swipeUp()
        sleep(1)
        snapshot("11-moment-grid")
        app.swipeDown()
        app.swipeDown()

        // Note
        notePrompt.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("The boat to the island, and the lemonade after.")
        snapshot("12-note-editor")
        app.buttons["Save"].tap()
        let savedNote = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "lemonade after")).firstMatch
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5), "Saved note is not shown")
        snapshot("13-moment-with-note")

        // Share card
        app.buttons["More"].tap()
        let share = app.buttons["Share"]
        if share.waitForExistence(timeout: 5) {
            share.tap()
            sleep(3)
            snapshot("14-share-card")
            if app.buttons["Done"].waitForExistence(timeout: 5) {
                app.buttons["Done"].tap()
            }
        }

        // Today and Us
        app.tabBars.buttons["Today"].tap()
        sleep(3)
        snapshot("15-today")
        describe(app, "today")
        app.swipeUp()
        sleep(1)
        snapshot("16-today-scrolled")
        app.tabBars.buttons["Us"].tap()
        sleep(1)
        snapshot("17-us")
        describe(app, "us")
    }

    /// Photo access is normally granted before the run with `simctl privacy`; if the system
    /// still asks, choose full access so the test-only import path is used.
    @MainActor
    private func allowPhotoAccessIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Allow Access to All Photos"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    /// Prints what the timeline shows so CI logs describe the generated story.
    @MainActor
    private func logMoments(in app: XCUIApplication) {
        let cards = app.buttons.matching(identifier: "momentCard").allElementsBoundByIndex
        print("TIMELINE: \(cards.count) moment cards loaded")
        for card in cards {
            print("TIMELINE MOMENT: \(card.label)")
        }
    }

    /// Prints the visible text of a screen so CI logs show what the user would read.
    @MainActor
    private func describe(_ app: XCUIApplication, _ screen: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        print("SCREEN \(screen): \(texts.joined(separator: " | "))")
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
