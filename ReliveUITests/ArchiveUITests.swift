import XCTest

/// Real Device Polish V1 with the sample library, as a free user: Today (hero, Made for You,
/// discoveries), the Story year control, and Us → Memories, Moments, Places — the whole archive
/// is browsable without Premium. Then the same screens in dark mode and at the largest text
/// size for review.
///
/// Screenshots start with "U" (or "X" on an iPhone SE, where CI runs this test again).
final class ArchiveUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayStoryYearsAndTheFreeArchive() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        try completeOnboarding(app)
        let prefix = app.windows.firstMatch.frame.height < 700 ? "X" : "U"

        // Today
        app.tabBars.buttons["Today"].tap()
        sleep(3)
        capture("\(prefix)00-today")
        let discoveries = app.buttons.matching(identifier: "todayDiscovery")
        print("SCREEN today-discoveries=\(discoveries.count)")
        XCTAssertLessThanOrEqual(discoveries.count, 2, "Today stays short")
        app.swipeUp()
        sleep(1)
        capture("\(prefix)01-today-more")
        if let discovery = discoveries.allElementsBoundByIndex.first(where: \.isHittable) {
            print("SCREEN today-discovery: \(discovery.label)")
            discovery.tap()
            sleep(2)
            XCTAssertFalse(paywall(app).exists, "a discovery opens the archive, never a paywall")
            capture("\(prefix)02-today-discovery-opened")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Story: the year control (the sample library spans New Year's Eve 2024 and 2025).
        app.tabBars.buttons["Story"].tap()
        let years = app.buttons["storyYearNavigator"]
        XCTAssertTrue(years.waitForExistence(timeout: 10), "No year control on a two-year story")
        print("SCREEN story-years: \(years.label) | \(years.value as? String ?? "")")
        capture("\(prefix)03-story")
        years.tap()
        let year2025 = app.buttons["2025"]
        XCTAssertTrue(year2025.waitForExistence(timeout: 5), "The years of the story are listed")
        capture("\(prefix)04-story-years-menu")
        year2025.tap()
        sleep(2)
        capture("\(prefix)05-story-2025")
        // The control shows the year on screen: after the jump, 2025.
        let showing2025 = expectation(for: NSPredicate(format: "value == %@", "Showing 2025"), evaluatedWith: years)
        wait(for: [showing2025], timeout: 8)
        XCTAssertTrue(app.staticTexts["2025"].firstMatch.exists, "the 2025 heading is there")
        years.tap()
        let latest = app.buttons["Latest Memories"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        sleep(2)
        capture("\(prefix)06-story-latest")

        // Us → the archive, free.
        app.tabBars.buttons["Us"].tap()
        let memories = app.buttons["usMemories"]
        XCTAssertTrue(memories.waitForExistence(timeout: 10), "Memories isn't a way into the archive")
        print("SCREEN us-memories: \(memories.label)")
        capture("\(prefix)07-us")
        memories.tap()
        let cells = app.buttons.matching(identifier: "archiveMemory")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "No memories to browse")
        XCTAssertFalse(paywall(app).exists, "browsing memories is free")
        sleep(1)
        capture("\(prefix)08-memories")
        cells.firstMatch.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "The memory did not open")
        sleep(1)
        capture("\(prefix)09-memory-open")
        close.tap()
        app.navigationBars.buttons.firstMatch.tap()

        let moments = app.buttons["usMoments"]
        XCTAssertTrue(moments.waitForExistence(timeout: 5))
        moments.tap()
        let rows = app.buttons.matching(identifier: "archiveMoment")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No moments to browse")
        sleep(1)
        capture("\(prefix)10-moments")
        rows.firstMatch.tap()
        sleep(2)
        XCTAssertFalse(paywall(app).exists, "a moment opens without Premium")
        capture("\(prefix)11-moment")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        app.navigationBars.buttons.firstMatch.tap()

        let places = app.buttons["usPlaces"]
        XCTAssertTrue(places.waitForExistence(timeout: 5))
        places.tap()
        let placeRows = app.buttons.matching(identifier: "archivePlace")
        XCTAssertTrue(placeRows.firstMatch.waitForExistence(timeout: 10), "No places to browse")
        sleep(1)
        capture("\(prefix)12-places")
        print("SCREEN places: \(placeRows.allElementsBoundByIndex.prefix(6).map(\.label).joined(separator: " | "))")
        placeRows.firstMatch.tap()
        sleep(2)
        capture("\(prefix)13-place")
        XCTAssertFalse(paywall(app).exists)
        app.terminate()

        // Review: dark mode and the largest text size.
        for (name, arguments) in [("dark", ["-ReliveUITestDarkMode"]),
                                  ("large", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let review = XCUIApplication()
            review.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "free"] + arguments
            review.launch()
            let digit = name == "dark" ? "8" : "9"
            XCTAssertTrue(review.tabBars.buttons["Today"].waitForExistence(timeout: 30))
            review.tabBars.buttons["Today"].tap()
            sleep(3)
            capture("\(prefix)\(digit)0-\(name)-today")
            review.tabBars.buttons["Story"].tap()
            let control = review.buttons["storyYearNavigator"]
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            XCTAssertTrue(control.isHittable, "the year control stays reachable (\(name))")
            sleep(1)
            capture("\(prefix)\(digit)1-\(name)-story")
            review.tabBars.buttons["Us"].tap()
            let row = review.buttons["usMemories"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            capture("\(prefix)\(digit)2-\(name)-us")
            row.tap()
            XCTAssertTrue(review.buttons.matching(identifier: "archiveMemory").firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            capture("\(prefix)\(digit)3-\(name)-memories")
            review.navigationBars.buttons.firstMatch.tap()
            let placesRow = review.buttons["usPlaces"]
            XCTAssertTrue(placesRow.waitForExistence(timeout: 5))
            placesRow.tap()
            XCTAssertTrue(review.buttons.matching(identifier: "archivePlace").firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            capture("\(prefix)\(digit)4-\(name)-places")
            review.terminate()
        }
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
        seeStory.tap()
        XCTAssertTrue(app.tabBars.buttons["Us"].waitForExistence(timeout: 10), "Main app did not appear")
    }

    @MainActor
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
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
