import XCTest

// Build 2 end-to-end: gaurava:// deep-link routing and the widget-privacy flow.
//
// Note on the deep link: an XCUITest process cannot run `xcrun simctl openurl`
// from its sandbox, so the test drives the *same* production routing code
// (`DeepLinkRoute.tab(for:)` -> `selectedTab`) via the `--gaurava-open-url`
// launch argument. The live `.onOpenURL` path and `simctl openurl` are covered
// by the scripted evidence-capture step / manual checklist.
@MainActor
final class DeepLinkPrivacyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeepLinkSelectsJabsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://jabs"
        ]
        app.launch()

        let jabs = app.gauravaTab(.jabs)
        XCTAssertTrue(jabs.waitForExistence(timeout: 10))
        XCTAssertTrue(jabs.isSelected, "Deep link gaurava://jabs should select the Jabs tab")
    }

    func testDeepLinkSelectsResultsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://results"
        ]
        app.launch()

        let results = app.gauravaTab(.results)
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        XCTAssertTrue(results.isSelected, "Deep link gaurava://results should select the Results tab")
    }

    func testWidgetWeightEntryDeepLinkPresentsAddWeightSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://add-weight"
        ]
        app.launch()

        let summary = app.gauravaTab(.summary)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.isSelected, "Weight entry route should land on Summary")
        XCTAssertTrue(app.descendants(matching: .any)["add-weight-sheet"].waitForExistence(timeout: 5))
    }

    func testWidgetJabEntryDeepLinkPresentsAddInjectionSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://add-injection"
        ]
        app.launch()

        let jabs = app.gauravaTab(.jabs)
        XCTAssertTrue(jabs.waitForExistence(timeout: 10))
        XCTAssertTrue(jabs.isSelected, "Jab entry route should land on Jabs")
        XCTAssertTrue(app.descendants(matching: .any)["add-injection-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["addInjectionFormSection"].exists)
    }

    func testWidgetDailyNoteDeepLinkPresentsDailyNoteSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://daily-note"
        ]
        app.launch()

        let summary = app.gauravaTab(.summary)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.isSelected, "Daily note route should land on Summary")
        XCTAssertTrue(app.navigationBars["Daily Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["daily-log-text-editor"].exists)
    }

    // Log v1.1: the single system capture entry point routes to the Log tab AND
    // presents the capture sheet (route-then-confirm). The symptom is written
    // only when the user taps a chip in-app — exercised here.
    func testLogSymptomDeepLinkPresentsCaptureSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://log-symptom"
        ]
        app.launch()

        let sheet = app.descendants(matching: .any)["log-capture-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "log-symptom deep link should present the capture sheet")

        // Tap a symptom inside the sheet (the write happens here, in-app, not in
        // the widget). Scope to the sheet so it is unambiguous vs. the Log tab.
        let nausea = sheet.buttons["side-effect-chip-nausea"].firstMatch
        XCTAssertTrue(nausea.waitForExistence(timeout: 5))
        nausea.tap()

        let severe = sheet.buttons["severity-choice-nausea-severe"].firstMatch
        XCTAssertTrue(severe.waitForExistence(timeout: 5), "The symptom row should include direct intensity choices")
        severe.tap()

        sheet.buttons["Done"].firstMatch.tap()

        let log = app.gauravaTab(.log)
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        XCTAssertTrue(log.isSelected, "After the capture sheet, the Log tab is selected")
    }

    func testWidgetPrivacyHideDetailsPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 10))
        app.gauravaTab(.care).tap()

        let row = app.descendants(matching: .any)["care-widget-privacy-row"]
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing widget privacy row")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        let hideOption = app.buttons["widget-privacy-option-redacted"]
        XCTAssertTrue(hideOption.waitForExistence(timeout: 5), "Menu option not presented")
        hideOption.tap()

        // The row value reflects the chosen mode.
        XCTAssertTrue(app.staticTexts["Hide details"].waitForExistence(timeout: 5))

        // And it survives a relaunch (App Group UserDefaults, per-device).
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.gauravaTab(.care).waitForExistence(timeout: 10))
        relaunched.gauravaTab(.care).tap()
        let relaunchedRow = relaunched.descendants(matching: .any)["care-widget-privacy-row"]
        for _ in 0..<8 where !relaunchedRow.exists { relaunched.swipeUp() }
        XCTAssertTrue(relaunchedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.staticTexts["Hide details"].exists)
    }
}
