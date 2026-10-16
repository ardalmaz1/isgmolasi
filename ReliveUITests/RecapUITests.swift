import XCTest

/// Monthly Recap 2.0 / Our Year 2.0 with the sample library:
/// free: Monthly Recap → Play → chapter by chapter → the Premium page (no paywall on open) →
/// See the Full Recap → paywall → close, back in the recap → the closing → Make Collage and
/// Share → paywall → close, back in the recap → Close. Relaunch as Premium: every chapter →
/// Make Collage → the collage opens with the recap's photos. Then dark mode, the largest
/// accessibility text size and Our Year, for review.
///
/// Screenshots start with "R" (or "E" on an iPhone SE, where CI runs this test again).
final class RecapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testRecapPreviewPremiumAndCreateFromIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        try completeOnboarding(app)
        let prefix = app.windows.firstMatch.frame.height < 700 ? "E" : "R"

        // Free: the recap opens without a paywall.
        try playMonthlyRecap(app)
        XCTAssertFalse(paywall(app).waitForExistence(timeout: 2), "opening a recap never shows the paywall")
        sleep(2)
        capture("\(prefix)01-month-opening")
        printScreen(app, "recap-opening")

        let seeAll = app.buttons["recapSeeAll"]
        let share = app.buttons["recapShareCard"]
        var step = 2
        while !seeAll.isHittable, !share.isHittable, app.buttons["recapNext"].isEnabled, step < 20 {
            next(app)
            capture("\(prefix)\(String(format: "%02d", step))-month-chapter")
            step += 1
        }
        if seeAll.isHittable {
            capture("\(prefix)10-month-premium-page")
            seeAll.tap()
            XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "See the Full Recap shows the paywall")
            capture("\(prefix)11-month-paywall")
            app.buttons["paywallClose"].tap()
            XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["recapClose"].waitForExistence(timeout: 5), "closing the paywall returns to the recap")
            next(app)
        }
        XCTAssertTrue(share.waitForExistence(timeout: 5), "the closing chapter is always reachable")
        reveal(app, share)
        XCTAssertTrue(share.isHittable, "Share is reachable on the closing chapter")
        capture("\(prefix)12-month-closing-free")

        // Creating and sharing from the recap follow the existing Premium rules.
        reveal(app, app.buttons["recapMakeCollage"])
        app.buttons["recapMakeCollage"].tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "creating from the full recap is Premium")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recapClose"].waitForExistence(timeout: 5))
        reveal(app, share)
        share.tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "sharing the recap card is Premium")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recapClose"].waitForExistence(timeout: 5))
        app.buttons["recapClose"].tap()
        XCTAssertTrue(app.buttons["recapClose"].waitForNonExistence(timeout: 5))
        app.terminate()

        // Premium, after a relaunch: every chapter, then make a collage from the recap.
        let premium = XCUIApplication()
        premium.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"]
        premium.launch()
        XCTAssertTrue(premium.tabBars.buttons["Create"].waitForExistence(timeout: 30), "Main app did not appear after relaunch")
        try playMonthlyRecap(premium)
        sleep(2)
        var chapters = 1
        while premium.buttons["recapNext"].isEnabled, chapters < 20 {
            XCTAssertFalse(premium.buttons["recapSeeAll"].isHittable, "Premium sees every chapter")
            next(premium)
            chapters += 1
            capture("\(prefix)\(String(format: "%02d", 12 + chapters))-month-premium-chapter")
        }
        print("SCREEN recap-premium-chapters: \(chapters)")
        let makeCollage = premium.buttons["recapMakeCollage"]
        reveal(premium, makeCollage)
        makeCollage.tap()
        XCTAssertFalse(paywall(premium).waitForExistence(timeout: 2), "Premium saw the paywall")
        XCTAssertTrue(premium.descendants(matching: .any)["collagePreview"].waitForExistence(timeout: 15), "The collage did not open from the recap")
        sleep(2)
        capture("\(prefix)40-collage-from-recap")
        premium.buttons["Close"].firstMatch.tap()
        sleep(1)

        // Our Year, when the sample library has one.
        for _ in 0..<3 where !premium.buttons["createOurYear"].exists {
            premium.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if try playOurYear(premium) {
            sleep(2)
            capture("\(prefix)50-year-opening")
            var index = 51
            while premium.buttons["recapNext"].isEnabled, index < 70 {
                next(premium)
                capture("\(prefix)\(index)-year-chapter")
                index += 1
            }
            premium.buttons["recapClose"].tap()
        }
        premium.terminate()

        // Review: dark mode and the largest accessibility text size.
        for (name, arguments) in [("dark", ["-ReliveUITestDarkMode"]),
                                  ("large-text", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let review = XCUIApplication()
            review.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"] + arguments
            review.launch()
            XCTAssertTrue(review.tabBars.buttons["Create"].waitForExistence(timeout: 30))
            try playMonthlyRecap(review)
            sleep(2)
            capture("\(prefix)80-\(name)-opening")
            next(review)
            capture("\(prefix)81-\(name)-chapter")
            XCTAssertTrue(review.buttons["recapClose"].isHittable, "Close stays reachable (\(name))")
            review.terminate()
        }
    }

    // MARK: - Steps

    /// Create → Monthly Recap → the first month with enough for a recap → Play.
    @MainActor
    private func playMonthlyRecap(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Create"].tap()
        tapClearOfTabBar(app, app.buttons["createMonthlyRecap"])
        let rows = app.buttons.matching(identifier: "recapMonthRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No months")
        let count = rows.count
        for index in 0..<min(count, 12) {
            let row = rows.element(boundBy: index)
            if !row.isHittable { app.swipeUp(); sleep(1) }
            row.tap()
            let play = app.buttons["recapPlay"]
            if play.waitForExistence(timeout: 5) {
                capture("R00-monthly-recap-with-play")
                // Let the photos below finish loading: a tap while the scroll view is still
                // settling can be taken as the start of a scroll.
                sleep(2)
                play.tap()
                let close = app.buttons["recapClose"]
                var attempt = 1
                while !close.waitForExistence(timeout: 8), attempt < 3 {
                    attempt += 1
                    printScreen(app, "recap-did-not-open-\(attempt)")
                    capture("R00-recap-did-not-open")
                    play.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.15)
                }
                print("SCREEN recap-open: opened=\(close.exists) attempts=\(attempt)")
                XCTAssertEqual(attempt, 1, "Play must open the recap on the first tap")
                XCTAssertTrue(close.exists, "The recap did not open")
                XCTAssertTrue(app.descendants(matching: .any)["recapProgress"].exists, "progress is always visible")
                XCTAssertTrue(app.buttons["recapNext"].waitForExistence(timeout: 30), "the recap's chapters never appeared")
                if app.buttons["recapNext"].isEnabled { return }
                // A quiet month is one honest page; look for a month with a story to tell.
                sleep(1)
                capture("R03-month-compact")
                printScreen(app, "recap-compact")
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            }
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        printScreen(app, "no-month-to-play")
        XCTFail("No month in the sample library has enough for a recap")
    }

    /// Create → Our Year → the first year → Play, if that year is one.
    @MainActor
    private func playOurYear(_ app: XCUIApplication) throws -> Bool {
        app.tabBars.buttons["Create"].tap()
        tapClearOfTabBar(app, app.buttons["createOurYear"])
        let yearRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Our 20")).firstMatch
        if yearRow.waitForExistence(timeout: 3) { yearRow.tap() }
        let play = app.buttons["yearPlay"]
        guard play.waitForExistence(timeout: 5) else {
            print("SCREEN our-year: not a year yet in the sample library")
            capture("R49-our-year-not-yet")
            return false
        }
        play.tap()
        XCTAssertTrue(app.buttons["recapClose"].waitForExistence(timeout: 15), "Our Year did not open")
        return true
    }

    @MainActor
    private func next(_ app: XCUIApplication) {
        let next = app.buttons["recapNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 30), "the recap's chapters never appeared")
        next.tap()
        sleep(1)
    }

    /// Scrolls the current page until `element` can be tapped (large text pushes it down).
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<6 where !(element.isHittable && element.frame.maxY < screen.maxY - 80) {
            app.swipeUp()
            sleep(1)
        }
    }

    private func paywall(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywallClose"]
    }

    @MainActor
    private func printScreen(_ app: XCUIApplication, _ name: String) {
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map { "\($0.identifier)=\($0.label)" }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        print("SCREEN \(name): buttons[\(buttons.joined(separator: " | "))] texts[\(texts.joined(separator: " | "))]")
    }

    @MainActor
    private func tapClearOfTabBar(_ app: XCUIApplication, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element.identifier) is missing")
        let screen = app.windows.firstMatch.frame
        // Any part of it in the band between the navigation bar and the tab bar is enough: at
        // the largest text sizes a tile can be taller than that band. Tap the middle of what's
        // visible there.
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
            printScreen(app, "not-reachable-\(element.identifier) frame=\(element.frame)")
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
    private func allowSystemAlertIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
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
