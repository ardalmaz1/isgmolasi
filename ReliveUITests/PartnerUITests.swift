import XCTest

/// Phase B — connecting a partner, with a scripted iCloud (`-RelivePartnerFake`): the
/// explanation, waiting for the partner, iCloud signed out, connected (owner and partner) and
/// the honest disconnect confirmations. Nothing here reaches CloudKit; the two-iPhone checks are
/// in docs/COUPLES_DEVICE_TEST_PLAN.md.
///
/// Screenshots start with "K".
final class PartnerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testConnectWaitDisconnectAndICloudStates() throws {
        // 1. Solo → explanation → invitation → waiting → cancel the invitation.
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveUITestImportAllPhotos", "-ReliveUITestStartFresh", "-ReliveStoreKit", "free", "-ReliveUITestNoHardPaywall", "-RelivePartnerFake", "available"]
        app.launch()
        try completeOnboarding(app)
        app.tabBars.buttons["Us"].tap()
        let connect = app.buttons["usConnectPartner"]
        scrollTo(connect, in: app)
        capture("K00-us-solo")
        connect.tap()
        let proceed = app.buttons["connectPartnerContinue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 5), "No explanation before connecting")
        for point in ["doesn’t upload your photo library", "No live location", "works fully on your own"] {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", point)).firstMatch.exists, "missing: \(point)")
        }
        capture("K01-connect-explanation")
        proceed.tap()
        let status = app.buttons["usPartnerStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "No invitation after Continue")
        print("SCREEN partner-waiting: \(status.label)")
        XCTAssertTrue(status.label.contains("Invitation sent"))
        XCTAssertTrue(app.buttons["usSendInvitation"].exists)
        capture("K02-us-waiting")
        status.tap()
        let disconnect = app.buttons["partnerDisconnect"]
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5))
        XCTAssertEqual(disconnect.label, "Cancel Invitation")
        capture("K03-partner-settings-waiting")
        disconnect.tap()
        confirm("Cancel Invitation", in: app, capturing: "K04-cancel-invitation-confirm")
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "Back to solo after cancelling")
        app.terminate()

        // 2. Signed out of iCloud: a calm message, and Relive carries on.
        let signedOut = launch(["-RelivePartnerFake", "noAccount"])
        signedOut.tabBars.buttons["Us"].tap()
        let connectAgain = signedOut.buttons["usConnectPartner"]
        scrollTo(connectAgain, in: signedOut)
        connectAgain.tap()
        signedOut.buttons["connectPartnerContinue"].tap()
        let message = signedOut.staticTexts["usPartnerMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        print("SCREEN partner-signed-out: \(message.label)")
        XCTAssertTrue(message.label.hasPrefix("Sign in to iCloud"))
        capture("K05-us-signed-out")
        signedOut.buttons["usPartnerMessageOK"].tap()
        XCTAssertTrue(connectAgain.waitForExistence(timeout: 5))
        signedOut.terminate()

        // 3. Connected, as the partner: "Leave Connection", explained honestly.
        let joined = launch(["-RelivePartnerFake", "partner"])
        joined.tabBars.buttons["Us"].tap()
        let connected = joined.buttons["usPartnerStatus"]
        scrollTo(connected, in: joined)
        print("SCREEN partner-connected: \(connected.label)")
        XCTAssertTrue(connected.label.contains("Connected with Emma"), "the partner's name comes from the couple name")
        capture("K06-us-connected")
        connected.tap()
        let leave = joined.buttons["partnerDisconnect"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        XCTAssertEqual(leave.label, "Leave Connection")
        leave.tap()
        confirm("Leave Connection", in: joined, capturing: "K07-leave-confirm")
        XCTAssertTrue(joined.buttons["usConnectPartner"].waitForExistence(timeout: 10))
        joined.terminate()

        // 4. Connected owner at the largest text size.
        let large = launch(["-RelivePartnerFake", "connected", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        large.tabBars.buttons["Us"].tap()
        let largeStatus = large.buttons["usPartnerStatus"]
        scrollTo(largeStatus, in: large)
        capture("K80-us-connected-large")
        largeStatus.tap()
        XCTAssertTrue(large.staticTexts["Your Partner"].waitForExistence(timeout: 5), "partner settings did not open")
        capture("K81-partner-settings-large")
        // At this size the button is below the explanation, outside the lazily built list.
        let largeDisconnect = large.buttons["partnerDisconnect"]
        scrollTo(largeDisconnect, in: large)
        XCTAssertEqual(largeDisconnect.label, "Disconnect Partner")
        capture("K82-partner-disconnect-large")
    }

    /// Relaunches without starting fresh: the story from step 1 is still there.
    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ReliveStoreKit", "free", "-ReliveUITestNoHardPaywall"] + arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Us"].waitForExistence(timeout: 15), "the story was not kept")
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) not found")
        sleep(1)
    }

    /// Taps the destructive button of the confirmation, after reading its explanation.
    @MainActor
    private func confirm(_ title: String, in app: XCUIApplication, capturing name: String) {
        let sheet = app.sheets.firstMatch
        let button: XCUIElement
        if sheet.waitForExistence(timeout: 3) {
            print("SCREEN confirm: \(sheet.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
            button = sheet.buttons[title].firstMatch
        } else {
            button = app.buttons.matching(identifier: "partnerDisconnectConfirm").firstMatch
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no confirmation for \(title)")
        capture(name)
        button.tap()
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
