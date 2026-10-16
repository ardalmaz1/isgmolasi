import XCTest

/// First Experience V2 with the sample library (full access is granted to the simulator before
/// the run): Welcome → partner → skip the date → "Let Relive find them" → what discovery does →
/// possible moments → keep / not ours → processing → "We found something for you." → open it →
/// close → Our Story. Then the first screens again in dark mode and at the largest text size.
///
/// Screenshots start with "N" (or "Q" on an iPhone SE, where CI runs this test again).
final class FirstExperienceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDiscoveryPathToFirstDiscoveryAndStory() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"]
        app.launch()
        let prefix = app.windows.firstMatch.frame.height < 700 ? "Q" : "N"

        // Welcome
        let findStory = app.buttons["onboardingFindStory"]
        XCTAssertTrue(findStory.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Your relationship, told through the photos you already have."].exists)
        capture("\(prefix)00-welcome")
        findStory.tap()

        // Partner
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Emma")
        capture("\(prefix)01-partner")
        nameField.typeText("\n")

        // Start date: skipped — no "together since" claims will be made.
        let skip = app.buttons["startDateSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startDateContinue"].isEnabled, "no relationship date is preselected")
        capture("\(prefix)02-start-date")
        skip.tap()

        // How to begin
        let discover = app.buttons["startDiscovery"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startManual"].exists, "the manual path is always there")
        capture("\(prefix)03-choose-start")
        discover.tap()

        // What discovery does, before any permission
        let proceed = app.buttons["discoveryContinue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["It may count faces in a few photos, but it doesn’t know who anyone is."].exists)
        capture("\(prefix)04-discovery-privacy")
        proceed.tap()
        let discoveryStarted = Date()
        allowSystemAlertIfShown()
        capture("\(prefix)05-discovery-progress")

        // Possible moments
        // On a slow simulator the system may still ask for Photos access after a few seconds.
        let keeps = app.buttons.matching(identifier: "candidateKeep")
        var waited = 0
        while !keeps.firstMatch.waitForExistence(timeout: 20), waited < 240 {
            waited += 20
            allowSystemAlertIfShown(timeout: 1)
        }
        XCTAssertTrue(keeps.firstMatch.exists, "No possible moments were suggested")
        print("SCREEN discovery-timing: possible moments after \(Int(Date().timeIntervalSince(discoveryStarted)))s (simulator, as seen by the test)")
        XCTAssertTrue(app.staticTexts["We found some moments that might belong in your story."].exists)
        sleep(2)
        capture("\(prefix)06-possible-moments")
        let kept = keepVisibleMoments(app)
        print("SCREEN discovery kept=\(kept)")
        XCTAssertGreaterThan(kept, 0)
        // The last one isn't ours.
        let notOurs = app.buttons.matching(identifier: "candidateNotOurs").allElementsBoundByIndex.last { $0.isHittable }
        notOurs?.tap()
        capture("\(prefix)07-decided")
        let continueButton = app.buttons["discoveryKeep"]
        XCTAssertTrue(continueButton.isEnabled)
        print("SCREEN discovery-continue: \(continueButton.label)")
        continueButton.tap()
        let processingStarted = Date()

        // Processing, then the first discovery
        sleep(3)
        capture("\(prefix)08-processing")
        let open = app.buttons["firstDiscoveryOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 300), "The first discovery did not appear")
        print("SCREEN processing-timing: first discovery after \(Int(Date().timeIntervalSince(processingStarted)))s (simulator, as seen by the test)")
        sleep(2)
        let headline = app.staticTexts["firstDiscoveryHeadline"].label
        let result = app.descendants(matching: .any)["firstDiscoveryResult"]
        print("SCREEN first-discovery: \(headline) | \(result.value as? String ?? "?") | \(result.label) | \(open.label)")
        XCTAssertEqual(headline, "We found something for you.")
        XCTAssertFalse(paywall(app).exists, "no paywall before the first discovery is experienced")
        capture("\(prefix)09-first-discovery")
        open.tap()

        // It opens in the app's own viewer or editor — never a paywall first.
        sleep(3)
        XCTAssertFalse(paywall(app).exists, "opening the first discovery never asks for Premium")
        capture("\(prefix)10-first-discovery-opened")
        closeWhateverIsOpen(app)

        // Our Story, without "together since" (the date was skipped).
        let storyTab = app.tabBars.buttons["Story"]
        XCTAssertTrue(storyTab.waitForExistence(timeout: 10))
        storyTab.tap()
        sleep(2)
        let header = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Since your first memory")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "no 'together since' claim without a date")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Together since")).firstMatch.exists)
        capture("\(prefix)11-story")
        // Us makes no relationship-duration claims without a date.
        app.tabBars.buttons["Us"].tap()
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Together since")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", ".*[0-9] days.*")).firstMatch.exists, "no days-together count")
        app.terminate()

        // Review: the first screens in dark mode and at the largest text size, plus the manual path.
        for (name, arguments) in [("dark", ["-ReliveUITestDarkMode"]),
                                  ("large", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let review = XCUIApplication()
            review.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free"] + arguments
            review.launch()
            let digit = name == "dark" ? "8" : "9"
            let start = review.buttons["onboardingFindStory"]
            XCTAssertTrue(start.waitForExistence(timeout: 15))
            capture("\(prefix)\(digit)0-\(name)-welcome")
            start.tap()
            let field = review.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("Emma\n")
            let date = review.buttons["startDateSkip"]
            XCTAssertTrue(date.waitForExistence(timeout: 5))
            XCTAssertFalse(review.buttons["startDateContinue"].isEnabled, "no date preselected (\(name))")
            capture("\(prefix)\(digit)1-\(name)-start-date")
            reveal(review, date)
            date.tap()
            XCTAssertTrue(review.buttons["startDiscovery"].waitForExistence(timeout: 5))
            capture("\(prefix)\(digit)2-\(name)-choose-start")
            review.buttons["startDiscovery"].tap()
            let next = review.buttons["discoveryContinue"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            capture("\(prefix)\(digit)3-\(name)-discovery-privacy")
            XCTAssertTrue(next.isHittable, "Continue stays reachable (\(name))")
            let manual = review.buttons["discoveryManualInstead"]
            reveal(review, manual)
            manual.tap()
            XCTAssertTrue(review.buttons["manualChoosePhotos"].waitForExistence(timeout: 5))
            capture("\(prefix)\(digit)4-\(name)-manual")
            XCTAssertTrue(review.buttons["manualChoosePhotos"].isHittable, "the manual path stays reachable (\(name))")
            review.terminate()
        }
    }

    // MARK: - Steps

    /// Taps Keep on every possible moment, scrolling through the list.
    @MainActor
    private func keepVisibleMoments(_ app: XCUIApplication) -> Int {
        var kept = 0
        var idleSwipes = 0
        for _ in 0..<60 where idleSwipes < 3 {
            let next = app.buttons.matching(identifier: "candidateKeep").allElementsBoundByIndex.first { $0.isHittable && !$0.isSelected && $0.frame.maxY < app.windows.firstMatch.frame.maxY - 160 }
            if let next {
                next.tap()
                kept += 1
                idleSwipes = 0
            } else {
                app.swipeUp(velocity: .slow)
                idleSwipes += 1
            }
        }
        return kept
    }

    @MainActor
    private func closeWhateverIsOpen(_ app: XCUIApplication) {
        for identifier in ["movieClose", "recapClose"] where app.buttons[identifier].exists {
            app.buttons[identifier].tap()
            sleep(2)
            return
        }
        // A moment opened in Story, or a creation editor with a Close/Back button.
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        sleep(2)
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
            sleep(1)
        }
    }

    private func paywall(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["paywallClose"]
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
