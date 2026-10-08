import XCTest

/// Commercial v1 with a fake App Store (`-ReliveStoreKit free|premium`), never a live purchase:
/// 1. a free user saves their first collage — free;
/// 2. the next save opens the paywall, which closes back to the collage;
/// 3. a Memory Book can be read in full before "Save Full Book" asks for Premium;
/// 4. subscribing in the paywall finishes saving the book, and Us shows Premium + Restore;
/// 5. after a relaunch the free creation is still used, and the recap shows its free preview;
/// 6. a Premium user saves again and again without a paywall.
///
/// Screenshots start with "M".
final class CommercialUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFreeCreationPaywallAndPremium() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        try completeOnboarding(app)

        // 1. The first creation is free
        app.tabBars.buttons["Create"].tap()
        let collageFromMoment = app.buttons["createCollageMoment"]
        XCTAssertTrue(collageFromMoment.waitForExistence(timeout: 10))
        tapClearOfTabBar(app, collageFromMoment)
        try pickFirstMoment(app)
        let preview = app.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Collage editor did not open")
        sleep(2)
        app.buttons["collageSave"].tap()
        allowSystemAlertIfShown()
        XCTAssertFalse(paywall(app).waitForExistence(timeout: 2), "The first creation must not hit the paywall")
        XCTAssertTrue(waitForExport(app), "The free collage was not saved")
        capture("M01-free-collage-saved")

        // 2. The next save opens the paywall; closing it returns to the collage
        changeStyle(app, preview)
        app.buttons["collageSave"].tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "The second save did not open the paywall")
        XCTAssertTrue(app.staticTexts["Keep making memories worth keeping"].exists)
        XCTAssertEqual(app.staticTexts["paywallContext"].label.lowercased(), "create without limits")
        let purchase = app.buttons["paywallPurchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 10), "No purchase button")
        XCTAssertTrue(app.buttons["paywallPlanAnnual"].waitForExistence(timeout: 10), "Prices did not load")
        XCTAssertTrue(app.buttons["paywallPlanMonthly"].exists)
        XCTAssertTrue(app.buttons["paywallPlanAnnual"].isSelected, "Annual is the recommended default")
        XCTAssertEqual(purchase.label, "Continue with Annual", "No trial is configured, so no trial wording")
        XCTAssertTrue(app.staticTexts["paywallDisclosure"].label.contains("Renews automatically"))
        XCTAssertTrue(app.buttons["paywallRestore"].exists, "Restore Purchases must be on the paywall")
        XCTAssertTrue(app.buttons["paywallTerms"].exists)
        XCTAssertTrue(app.buttons["paywallPrivacy"].exists)
        sleep(1)
        capture("M02-paywall-collage")
        print("SCREEN paywall: \(app.staticTexts["paywallDisclosure"].label)")
        app.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 10), "The paywall did not close")
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "Closing the paywall did not return to the collage")
        XCTAssertFalse(app.descendants(matching: .any)["exportFinished"].exists, "Nothing was saved behind the paywall")
        capture("M03-back-to-collage")
        app.buttons["Close"].firstMatch.tap()

        // 3. A Memory Book is read in full before saving asks for Premium
        let startBook = app.buttons["createBook"]
        XCTAssertTrue(startBook.waitForExistence(timeout: 10))
        tapClearOfTabBar(app, startBook)
        let fromTrip = app.buttons["A Trip"]
        XCTAssertTrue(fromTrip.waitForExistence(timeout: 5), "No trips to make a book from")
        fromTrip.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "periodPickerRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No trips listed")
        sleep(1)
        let trip = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isEnabled && $0.isHittable }, "No trip with enough photos")
        trip.tap()
        let pages = app.descendants(matching: .any)["bookPages"]
        let pageLabel = app.staticTexts["bookPageLabel"]
        XCTAssertTrue(pages.waitForExistence(timeout: 10), "The book did not open")
        sleep(2)
        pages.swipeLeft()
        sleep(1)
        pages.swipeLeft()
        sleep(2)
        XCTAssertTrue(pageLabel.label.hasPrefix("Page"), "The free preview should turn pages: \(pageLabel.label)")
        XCTAssertFalse(paywall(app).exists, "Reading a book never asks for Premium")
        capture("M04-book-preview")
        app.buttons["bookSaveFullBook"].tap()
        XCTAssertTrue(paywall(app).waitForExistence(timeout: 10), "Save Full Book did not open the paywall")
        XCTAssertEqual(app.staticTexts["paywallContext"].label.lowercased(), "keep this book")
        XCTAssertTrue(app.buttons["paywallPlanAnnual"].waitForExistence(timeout: 10))
        sleep(1)
        capture("M05-paywall-book")

        // 4. Subscribing finishes saving the book
        app.buttons["paywallPurchase"].tap()
        XCTAssertTrue(paywall(app).waitForNonExistence(timeout: 15), "The paywall did not close after subscribing")
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(app), "The book was not saved after subscribing")
        let finished = app.descendants(matching: .any)["exportFinished"]
        print("SCREEN book-saved: \(finished.label)")
        XCTAssertTrue(finished.label.contains("saved to Photos") || finished.label.contains("Saved to Photos"))
        capture("M06-book-saved-after-subscribing")
        app.buttons["Close"].firstMatch.tap()

        app.tabBars.buttons["Us"].tap()
        let premiumRow = app.buttons["usPremium"]
        XCTAssertTrue(premiumRow.waitForExistence(timeout: 10))
        XCTAssertTrue(premiumRow.label.contains("Active"), "Us does not show Premium: \(premiumRow.label)")
        XCTAssertTrue(app.buttons["usRestore"].exists, "Restore Purchases must be in Us")
        capture("M07-us-premium")
        app.terminate()

        // 5. Relaunch as free (the fake App Store forgets the purchase): the free creation is
        //    still used, and the recap shows its free preview
        let free = XCUIApplication()
        free.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "free"]
        free.launch()
        XCTAssertTrue(free.tabBars.buttons["Create"].waitForExistence(timeout: 30), "Main app did not appear after relaunch")
        free.tabBars.buttons["Create"].tap()
        let collageAgain = free.buttons["createCollageMoment"]
        XCTAssertTrue(collageAgain.waitForExistence(timeout: 10))
        tapClearOfTabBar(free, collageAgain)
        try pickFirstMoment(free)
        XCTAssertTrue(free.descendants(matching: .any)["collagePreview"].waitForExistence(timeout: 10))
        sleep(2)
        free.buttons["collageSave"].tap()
        XCTAssertTrue(paywall(free).waitForExistence(timeout: 10), "The free creation was given again after a relaunch")
        free.buttons["paywallClose"].tap()
        XCTAssertTrue(paywall(free).waitForNonExistence(timeout: 10))
        free.buttons["Close"].firstMatch.tap()

        let recap = free.buttons["createMonthlyRecap"]
        XCTAssertTrue(recap.waitForExistence(timeout: 10))
        tapClearOfTabBar(free, recap)
        let month = free.buttons.matching(identifier: "recapMonthRow").firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 10), "No months")
        month.tap()
        let unlock = free.buttons["recapUnlock"]
        let few = free.staticTexts["Just a few memories this month"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10) || few.exists, "The recap shows neither its preview nor its honest empty state")
        sleep(1)
        capture("M08-recap-free-preview")
        free.terminate()

        // 6. Premium: saving again and again never shows the paywall
        let premium = XCUIApplication()
        premium.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveStoreKit", "premium"]
        premium.launch()
        XCTAssertTrue(premium.tabBars.buttons["Create"].waitForExistence(timeout: 30))
        premium.tabBars.buttons["Create"].tap()
        let premiumCollage = premium.buttons["createCollageMoment"]
        XCTAssertTrue(premiumCollage.waitForExistence(timeout: 10))
        tapClearOfTabBar(premium, premiumCollage)
        try pickFirstMoment(premium)
        let premiumPreview = premium.descendants(matching: .any)["collagePreview"]
        XCTAssertTrue(premiumPreview.waitForExistence(timeout: 10))
        sleep(2)
        premium.buttons["collageSave"].tap()
        allowSystemAlertIfShown()
        XCTAssertTrue(waitForExport(premium), "Premium could not save")
        changeStyle(premium, premiumPreview)
        premium.buttons["collageSave"].tap()
        XCTAssertFalse(paywall(premium).waitForExistence(timeout: 3), "Premium saw the paywall")
        XCTAssertTrue(waitForExport(premium), "Premium could not save again")
        capture("M09-premium-saved-again")
    }

    // MARK: - Steps

    private func paywall(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywallClose"]
    }

    /// Picks a different collage style so Save is enabled again.
    @MainActor
    private func changeStyle(_ app: XCUIApplication, _ preview: XCUIElement) {
        let style = preview.label.contains("Film") ? "Grid" : "Film"
        let button = app.buttons[style].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        var scrolled = 0
        while !(button.isHittable && button.frame.maxY < screen.maxY - 200), scrolled < 4 {
            app.swipeUp()
            sleep(1)
            scrolled += 1
        }
        button.tap()
        for _ in 0..<scrolled { app.swipeDown() }
        sleep(1)
        XCTAssertTrue(preview.label.contains(style), "The style did not change: \(preview.label)")
    }

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

    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) throws {
        let findStory = app.buttons["Find Our Story"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        XCTAssertFalse(paywall(app).exists, "No paywall at launch")
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
        XCTAssertFalse(paywall(app).exists, "No paywall after onboarding")
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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
