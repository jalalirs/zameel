import XCTest

/// Drills through the main flow against the live backend using the seeded
/// Japan-Korea trip. Requires a token already present in the app's defaults
/// (injected via `simctl spawn booted defaults write com.jalalirs.Zameel token …`).
final class TripFlowTests: XCTestCase {
    func testBrowseSeededTrip() {
        let app = XCUIApplication()
        app.launch()

        // Clear any stray system alert (e.g. notification prompts from other apps).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Don't Allow"].waitForExistence(timeout: 2) {
            springboard.buttons["Don't Allow"].tap()
        }

        // If we land on the login screen, sign in for real.
        let emailField = app.textFields["Email"]
        if emailField.waitForExistence(timeout: 4) {
            emailField.tap()
            emailField.typeText("jalalirs@gmail.com")
            let pw = app.secureTextFields["Password"]
            pw.tap()
            pw.typeText("zameel123")
            app.buttons["Sign in"].tap()
        }

        // Trips list → trip
        let trip = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Japan & Korea'")).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 10), "seeded trip should be listed")
        trip.tap()

        // Trip detail: hero budget card + cities + quick links
        XCTAssertTrue(app.staticTexts["Remaining"].waitForExistence(timeout: 10), "hero budget")
        XCTAssertTrue(app.staticTexts["Osaka"].waitForExistence(timeout: 5), "city row")
        XCTAssertTrue(app.staticTexts["Travelers"].exists, "travelers link")

        // Budget screen and back
        app.staticTexts["Budget & spending"].tap()
        XCTAssertTrue(app.staticTexts["By category"].waitForExistence(timeout: 5), "budget breakdown")
        XCTAssertTrue(app.staticTexts["Your spending"].exists, "own personal budget section")
        app.navigationBars.buttons.firstMatch.tap()

        // City → attraction detail
        XCTAssertTrue(app.staticTexts["Osaka"].waitForExistence(timeout: 5))
        app.staticTexts["Osaka"].tap()
        XCTAssertTrue(app.navigationBars["Osaka"].waitForExistence(timeout: 5), "city view opened")
        // Match the row button, not the city-header text that also mentions USJ.
        let usj = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Universal Studios'")).firstMatch
        XCTAssertTrue(usj.waitForExistence(timeout: 5), "USJ attraction in Osaka")
        usj.tap()
        XCTAssertTrue(app.navigationBars["Attraction"].waitForExistence(timeout: 5), "attraction opened")
        XCTAssertTrue(app.buttons["Edit cost / mark paid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Remind me when booking opens"].exists, "USJ booking reminder")
        // Photos section sits below the booking section — scroll to it.
        let attach = app.buttons["Attach photos from library"]
        for _ in 0..<6 where !attach.exists { app.swipeUp() }
        XCTAssertTrue(attach.exists)
        XCTAssertTrue(app.buttons["Find photos taken here"].exists, "location matcher offered")

        // Back to trip detail, then scroll down to the flights section.
        app.navigationBars["Attraction"].buttons.firstMatch.tap()
        app.navigationBars["Osaka"].buttons.firstMatch.tap()
        let medina = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Medina MED → Seoul ICN'")).firstMatch
        // Scroll until the row is actually tappable; recover if we overshoot.
        for _ in 0..<8 where !medina.isHittable { app.swipeUp() }
        for _ in 0..<3 where !medina.isHittable { app.swipeDown() }
        XCTAssertTrue(medina.isHittable, "booked flight leg Medina → Seoul")

        // The booked flight carries the Qatar Airways confirmation attachment
        // (section sits low in the form — scroll until it materializes).
        medina.tap()
        let attachment = app.staticTexts["QatarAirways-8UTU58.html"]
        for _ in 0..<8 where !attachment.exists { app.swipeUp() }
        XCTAssertTrue(attachment.exists, "booking email attached")
    }
}
