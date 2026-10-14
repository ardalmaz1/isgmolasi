import XCTest

/// Made for You on a free account with the sample library:
/// Create → Made for You → open the suggestion (no paywall) → its prepared creation → edit →
/// attempt export → the existing Premium / free-creation rules. Then Today, "Not now", and the
/// same Create screen in dark mode and at a large text size for review.
///
/// Screenshots start with "F".
final class MadeForYouUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMadeForYouOpensAPreparedCreation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        try completeOnboarding(app)

        app.tabBars.buttons["Create"].tap()
        let cards = app.buttons.matching(identifier: "madeForYouCard")
        if !cards.firstMatch.waitForExistence(timeout: 15) {
            let buttons = app.buttons.allElementsBoundByIndex.prefix(30).map { "\($0.identifier)=\($0.label)" }
            print("SCREEN create-without-cards: \(buttons.joined(separator: " | "))")
            capture("F00-no-cards")
        }
        XCTAssertTrue(cards.firstMatch.exists, "Made for You found nothing in the sample library")
        sleep(2)
        capture("F01-create-made-for-you")
        let all = cards.allElementsBoundByIndex
        for card in all { print("SCREEN made-for-you: \(card.value as? String ?? "?") | \(card.label)") }
        XCTAssertLessThanOrEqual(all.count, 4, "a few suggestions, never a feed")

        // Prefer a prepared creation (book, story, collage) over a recap.
        let preferred = ["book", "story", "collage", "monthlyRecap", "yearInReview"]
        let card = try XCTUnwrap(preferred.lazy.compactMap { kind in all.first { ($0.value as? String) == kind } }.first)
        let kind = card.value as? String ?? ""
        card.tap()
        XCTAssertFalse(paywall(app).waitForExistence(timeout: 3), "opening a suggestion never shows the paywall")

        switch kind {
        case "book":
            let pages = app.descendants(matching: .any)["bookPages"]
            XCTAssertTrue(pages.waitForExistence(timeout: 15), "The prepared book did not open")
            sleep(2)
            capture("F02-prepared-book")
            pages.swipeLeft()
            sleep(1)
            app.buttons["bookEdit"].tap()
            XCTAssertTrue(app.buttons["bookEditDone"].waitForExistence(timeout: 10))
            app.buttons["Film"].firstMatch.tap()
            sleep(1)
            app.buttons["bookEditDone"].tap()
            sleep(2)
            app.buttons["bookSaveFullBook"].tap()
            XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "a book still needs Premium to keep")
            capture("F03-book-export-paywall")
            app.buttons["paywallClose"].tap()
            XCTAssertTrue(pages.waitForExistence(timeout: 10))
            app.buttons["Close"].firstMatch.tap()
        case "story", "collage":
            let preview = app.descendants(matching: .any)[kind == "story" ? "storyCards" : "collagePreview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 15), "The prepared \(kind) did not open")
            sleep(2)
            capture("F02-prepared-\(kind)")
            let save = app.buttons[kind == "story" ? "storySaveAll" : "collageSave"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            save.tap()
            allowSystemAlertIfShown()
            XCTAssertTrue(waitForExport(app), "the first creation is free")
            capture("F03-free-export")
            app.buttons["Close"].firstMatch.tap()
        default:
            // A recap: the immersive recap, with its free preview.
            XCTAssertTrue(app.buttons["recapClose"].waitForExistence(timeout: 15), "The recap did not open")
            sleep(2)
            capture("F02-recap")
            app.buttons["recapClose"].tap()
        }

        // Today shows at most one Made for You card.
        app.tabBars.buttons["Today"].tap()
        sleep(2)
        XCTAssertLessThanOrEqual(app.descendants(matching: .any).matching(identifier: "madeForYouToday").count, 1)
        capture("F04-today")

        // "Not now" takes a suggestion away and it stays away.
        app.tabBars.buttons["Create"].tap()
        let first = cards.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let dismissedLabel = first.label
        first.press(forDuration: 1.2)
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        notNow.tap()
        sleep(2)
        XCTAssertFalse(cards.allElementsBoundByIndex.contains { $0.label == dismissedLabel }, "dismissed")
        capture("F05-after-not-now")
        app.terminate()

        // Review: dark mode and a large text size, same library and history.
        let dark = XCUIApplication()
        dark.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "free", "-ReliveUITestDarkMode"]
        dark.launch()
        XCTAssertTrue(dark.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        dark.tabBars.buttons["Create"].tap()
        sleep(3)
        XCTAssertFalse(dark.buttons.matching(identifier: "madeForYouCard").allElementsBoundByIndex.contains { $0.label == dismissedLabel }, "still dismissed after a relaunch")
        capture("F06-create-dark")
        dark.terminate()

        let large = XCUIApplication()
        large.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "free",
                                  "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        large.launch()
        XCTAssertTrue(large.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        large.tabBars.buttons["Create"].tap()
        sleep(3)
        capture("F07-create-large-text")
    }

    // MARK: - Steps

    private func paywall(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywallClose"]
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
