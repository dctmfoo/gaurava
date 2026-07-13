import XCTest

// Build 4 end-to-end: the injection-day Live Activity's app-side touch points
// that CAN be scripted in the simulator — the completion deep-link landing and
// the Care opt-in toggle. Starting/updating an actual Live Activity and the
// Dynamic Island presentation need a device (see the build report's manual
// checklist); here we assert the in-app state those surfaces route to.
//
// As in Build 2/3, the deep link is driven via the `--gaurava-open-url` launch
// argument (an XCUITest sandbox can't run `xcrun simctl openurl`), exercising
// the same DeepLinkRoute + routing code as a live `gaurava://` open.
@MainActor
final class LiveActivityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInjectionConfirmationDeepLinkOpensPrefilledAddInjection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-open-url", "gaurava://jab-confirm"
        ]
        app.launch()

        // Lands on the Jabs tab...
        let jabs = app.gauravaTab(.jabs)
        XCTAssertTrue(jabs.waitForExistence(timeout: 10))
        XCTAssertTrue(jabs.isSelected, "Completion link should select the Jabs tab")

        // ...and presents the prefilled Add Injection confirmation sheet.
        let sheet = app.descendants(matching: .any)["add-injection-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Confirmation link should present the prefilled Add Injection sheet")
    }

    func testLiveActivityOptInPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 10))
        app.gauravaTab(.care).tap()

        let row = app.descendants(matching: .any)["care-live-activity-row"]
        for _ in 0..<10 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing Live Activity opt-in row")
        if !row.isHittable { app.swipeUp() }
        row.tap()

        let onOption = app.buttons["live-activity-option-on"]
        XCTAssertTrue(onOption.waitForExistence(timeout: 5), "Opt-in menu not presented")
        onOption.tap()

        XCTAssertTrue(app.staticTexts["On"].waitForExistence(timeout: 5), "Row should reflect the On state")

        // Survives a relaunch (App Group UserDefaults, per-device).
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.gauravaTab(.care).waitForExistence(timeout: 10))
        relaunched.gauravaTab(.care).tap()
        let relaunchedRow = relaunched.descendants(matching: .any)["care-live-activity-row"]
        for _ in 0..<10 where !relaunchedRow.exists { relaunched.swipeUp() }
        XCTAssertTrue(relaunchedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.staticTexts["On"].exists, "Opt-in should persist across launches")
    }
}
