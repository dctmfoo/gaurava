import XCTest

/// i18n regression guard for the F1 fix: asserts the ProvisionalInjectionCard (the
/// "Planned for every {weekday}" recurrence card) renders under hi/ta/te on both
/// the Summary and Jabs tabs. Drives the real onboarding flow with the injection
/// day enabled (defaults to Monday) and zero jabs logged — the exact state that
/// renders the card — using identifier-based selectors so it is language-neutral.
/// Assertion-only (no screenshot attachments): the card's presence in each locale
/// is the value, not a captured image.
@MainActor
final class ProvisionalCardLocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHindiProvisionalCard() throws { try assertProvisionalCard(code: "hi", locale: "hi_IN") }
    func testTamilProvisionalCard() throws { try assertProvisionalCard(code: "ta", locale: "ta_IN") }
    func testTeluguProvisionalCard() throws { try assertProvisionalCard(code: "te", locale: "te_IN") }

    private func assertProvisionalCard(code: String, locale: String) throws {
        let app = XCUIApplication()
        // Deep-link into the "Just starting" branch (status pre-set) so the weekly
        // injection-day plan is reachable; the branch lands on the medicine step.
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run",
            "--gaurava-first-run-branch", "startingNow",
            "-AppleLanguages", "(\(code))",
            "-AppleLocale", locale
        ]
        app.launch()
        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 10),
                      "onboarding did not appear for \(code)")

        // Advance medicine → weekly-plan, then enable the injection day (Monday default).
        app.buttons["firstRunContinue"].tap()
        let mondayChip = app.buttons["firstRunInjectionDay-1"]
        var tries = 0
        while !mondayChip.exists && tries < 5 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(mondayChip.waitForExistence(timeout: 5), "weekday chip missing for \(code)")
        if !mondayChip.isHittable { app.swipeUp() }
        mondayChip.tap()
        XCTAssertTrue(app.revealFirstRunInjectionDayPicker().exists)

        // Advance weekly-plan → reminders → Apple Health → the mandatory weight
        // baseline, then Finish into the tab shell.
        app.buttons["firstRunContinue"].tap()          // weekly-plan → reminders
        let bridge = app.buttons["firstRunContinue"]
        XCTAssertTrue(bridge.waitForExistence(timeout: 5))
        if !bridge.isHittable { app.swipeUp() }
        bridge.tap()                                   // reminders → Apple Health
        app.fillMandatoryOnboardingWeights(current: "90") // Apple Health → … → close

        let close = app.descendants(matching: .any)["firstRunClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "did not reach onboarding close screen for \(code)")
        let done = app.buttons["firstRunContinue"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        if !done.isHittable { app.swipeUp() }
        done.tap()

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 10),
                      "tab shell not reached for \(code)")

        // Summary tab — provisional card near the top.
        let summaryCard = app.descendants(matching: .any)["provisionalInjectionCard"]
        XCTAssertTrue(summaryCard.waitForExistence(timeout: 8),
                      "no provisional card on Summary for \(code)")

        // Jabs tab — the merged first-jab anticipation card (the weekday plan +
        // the log CTA in one). Tap by SF-Symbol identifier (language-neutral; the
        // visible label is localized).
        app.gauravaTab(.jabs).tap()
        let jabsCard = app.descendants(matching: .any)["jabsFirstJabAnticipation"]
        XCTAssertTrue(jabsCard.waitForExistence(timeout: 8),
                      "no first-jab anticipation card on Jabs for \(code)")
    }
}
