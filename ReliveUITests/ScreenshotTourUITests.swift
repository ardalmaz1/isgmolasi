import XCTest

/// Walks the app for App Store screenshots and writes full-resolution PNGs to the folder in
/// `YUVI_SHOTS` (pass `TEST_RUNNER_YUVI_SHOTS=<dir>` to xcodebuild). Skipped everywhere else,
/// including CI. Expects a library of dated, located photos (see `docs/APP_STORE.md` → Screenshots)
/// and photo access granted beforehand.
final class ScreenshotTourUITests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["YUVI_SHOTS"], "screenshot runs only")
        folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override class var defaultTestSuite: XCTestSuite {
        ProcessInfo.processInfo.environment["YUVI_SHOTS"] == nil ? XCTestSuite(name: "skipped") : super.defaultTestSuite
    }

    @MainActor
    func test1Onboarding() throws {
        let app = launch(fresh: true)
        let findStory = app.buttons["Find Our Story"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        sleep(2)
        save("01-welcome")
        findStory.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Emma\n")
        XCTAssertTrue(app.staticTexts["When did your story begin?"].waitForExistence(timeout: 5))
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "March")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "2024")
        app.buttons["startDateContinue"].tap()
        let manual = app.buttons["startManual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        let choose = app.buttons["Choose Our Photos"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        allowSystemAlertIfShown()
        sleep(3)
        save("02-processing")
        let seeStory = app.buttons["See Our Story"]
        var waited = 0
        while !seeStory.waitForExistence(timeout: 30), waited < 330 {
            waited += 30
            allowSystemAlertIfShown()
        }
        sleep(4)
        save("03-reveal")
        seeStory.tap()
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 10))
        sleep(4)
        save("04-story-top")
        app.swipeUp()
        sleep(2)
        save("05-story-scrolled")
        app.swipeUp()
        sleep(2)
        save("06-story-scrolled2")
    }

    @MainActor
    func test2Screens() throws {
        let app = launch(fresh: false)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        sleep(3)

        // Story: a moment
        app.tabBars.buttons["Story"].tap()
        sleep(2)
        let cards = app.buttons.matching(identifier: "momentCard")
        if cards.firstMatch.waitForExistence(timeout: 10) {
            cards.firstMatch.tap()
            sleep(3)
            save("10-moment")
            app.swipeUp()
            sleep(2)
            save("11-moment-scrolled")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Today
        app.tabBars.buttons["Today"].tap()
        sleep(4)
        save("20-today")
        app.swipeUp()
        sleep(2)
        save("21-today-scrolled")

        // Create
        app.tabBars.buttons["Create"].tap()
        sleep(3)
        save("30-create")
        app.swipeUp()
        sleep(2)
        save("31-create-scrolled")
        app.swipeDown()
        app.swipeDown()

        // Us
        app.tabBars.buttons["Us"].tap()
        sleep(3)
        save("40-us")
        app.swipeUp()
        sleep(2)
        save("41-us-scrolled")
    }

    @MainActor
    func test3Recap() throws {
        let app = launch(fresh: false)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Create"].tap()
        tapClearOfTabBar(app, app.buttons["createMonthlyRecap"])
        let rows = app.buttons.matching(identifier: "recapMonthRow")
        guard rows.firstMatch.waitForExistence(timeout: 10) else { return XCTFail("No months") }
        sleep(2)
        save("50-recap-months")
        for index in 0..<min(rows.count, 8) {
            let row = rows.element(boundBy: index)
            if !row.isHittable { app.swipeUp(); sleep(1) }
            row.tap()
            let play = app.buttons["recapPlay"]
            if play.waitForExistence(timeout: 5) {
                sleep(3)
                save("51-recap-month-\(index)")
                play.tap()
                let next = app.buttons["recapNext"]
                if next.waitForExistence(timeout: 30), next.isEnabled {
                    sleep(3)
                    save("52-recap-\(index)-chapter0")
                    for step in 1..<8 where next.exists && next.isEnabled {
                        next.tap()
                        sleep(3)
                        save("52-recap-\(index)-chapter\(step)")
                    }
                    app.buttons["recapClose"].tap()
                    return
                }
                app.buttons["recapClose"].tap()
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
    }

    @MainActor
    func test4Movie() throws {
        let app = launch(fresh: false)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Create"].tap()
        tapClearOfTabBar(app, app.buttons["createMovie"])
        sleep(1)
        app.buttons["movieSourceTrip"].tap()
        let trips = app.descendants(matching: .any).matching(identifier: "periodPickerRow")
        guard trips.firstMatch.waitForExistence(timeout: 10) else { return XCTFail("No trips") }
        save("60-trips")
        trips.firstMatch.tap()
        let preview = app.descendants(matching: .any)["moviePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        sleep(4)
        save("61-movie-editor")
        app.buttons["moviePlay"].tap()
        sleep(3)
        save("62-movie-playing")
        sleep(3)
        save("63-movie-playing2")
    }

    @MainActor
    func test5Book() throws {
        let app = launch(fresh: false)
        XCTAssertTrue(app.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Create"].tap()
        tapClearOfTabBar(app, app.buttons["createBook"])
        sleep(5)
        save("70-book")
        app.swipeLeft()
        sleep(3)
        save("71-book-page")
        app.swipeLeft()
        sleep(3)
        save("72-book-page2")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium", "-RelivePartnerFake", "connected"]
        if fresh { app.launchArguments.append("-ReliveUITestStartFresh") }
        app.launch()
        return app
    }

    @MainActor
    private func save(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func tapClearOfTabBar(_ app: XCUIApplication, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element.identifier) is missing")
        let screen = app.windows.firstMatch.frame
        let top = screen.minY + 100, bottom = screen.maxY - 110
        for _ in 0..<20 where !(element.frame.midY > top && element.frame.midY < bottom) {
            if element.frame.midY > (top + bottom) / 2 { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
            sleep(1)
        }
        element.tap()
    }

    @MainActor
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
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
}
