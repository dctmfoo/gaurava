import XCTest

/// Walks every row of the post-onboarding combination matrix (the appendix of
/// docs/post-onboarding-adaptive-states-plan.html: 8 Summary layouts + 2 Jabs
/// layouts) and asserts the resulting state. Assertion-only regression coverage — no
/// screenshot attachments (the owner does not review the .xcresult images; the
/// assertions are the value).
///
/// Setup is decoupled from onboarding. The mandatory hard gate
/// (docs/onboarding-baseline-split-plan.html v1.3) means a fresh install now always
/// commits a complete weight baseline, so the partial/legacy data shapes below are no
/// longer onboarding-reachable — they are still real for legacy installs, Apple Health
/// imports, and CloudKit-synced devices with gaps. Each row seeds its exact SwiftData
/// state directly via `--gaurava-seed-*` launch args (see `TestStateSeedLaunchHandler`),
/// which both restores this coverage and makes these data-driven surface tests
/// independent of the onboarding flow.
@MainActor
final class AdaptiveStatesMatrixUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Harness

    /// Reset to a clean tab shell, then seed the requested state. The reset lands in
    /// the tab shell (no `--gaurava-show-first-run`), and `TestStateSeedLaunchHandler`
    /// writes the records right after, so we never touch onboarding. An empty `args`
    /// list is the pure-skip state (first-run complete, no data).
    private func launchSeeded(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"] + args
        app.launch()
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 8), "did not reach tab shell")
        return app
    }

    private func startingNowProfile(_ extra: [String]) -> [String] {
        ["--gaurava-seed-profile", "--gaurava-seed-status", "startingNow"] + extra
    }

    private func gotoJabs(_ app: XCUIApplication) {
        app.gauravaTab(.jabs).tap()
        // Bucket B now shows the merged anticipation card (no "No jabs logged
        // yet"), so anchor on the always-present toolbar Add button.
        XCTAssertTrue(app.buttons["jabsAddInjection"].waitForExistence(timeout: 5))
    }

    /// Combined-accessibility elements (the provisional card, the metric tiles)
    /// aren't reliably typed as buttons/staticTexts, so match by identifier
    /// across all descendants.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    // MARK: - Summary matrix (CW x GW x ID, plus the hasProfile split)

    func testState01PureSkip() throws {
        let app = launchSeeded([])
        XCTAssertTrue(app.staticTexts["Your timeline starts here"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["summarySetNumbers"].exists)
    }

    func testState02ProfileOnly() throws {
        let app = launchSeeded(startingNowProfile(["--gaurava-seed-starting", "98"]))
        // Profile exists but no weight: "Add today's weight", no "-- kg".
        XCTAssertTrue(app.buttons["summaryHeroAddWeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["summaryLogFirstInjection"].exists)
    }

    func testState03InjectionDayOnly() throws {
        let app = launchSeeded(startingNowProfile(["--gaurava-seed-injection-day", "1"]))
        XCTAssertTrue(app.buttons["summaryHeroAddWeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "provisionalInjectionCard").exists)
        // Same run checks the Jabs anticipation layout (weekday plan, zero jabs):
        // the merged card replaces the stat grid until the first logged jab.
        gotoJabs(app)
        XCTAssertTrue(element(app, "jabsFirstJabAnticipation").exists)
        XCTAssertFalse(element(app, "jabs-total-count").exists)
    }

    func testState04GoalOnly() throws {
        let app = launchSeeded(startingNowProfile(["--gaurava-seed-goal", "80"]))
        XCTAssertTrue(app.buttons["summaryHeroAddWeight"].waitForExistence(timeout: 5))
        // The hero shows start/goal as one reference line ("Goal 80 kg"), not a
        // standalone "Goal" boundary label.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Goal'")).firstMatch.exists)
    }

    func testState05GoalPlusInjectionDay() throws {
        let app = launchSeeded(startingNowProfile(["--gaurava-seed-goal", "80", "--gaurava-seed-injection-day", "1"]))
        XCTAssertTrue(app.buttons["summaryHeroAddWeight"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "provisionalInjectionCard").exists)
    }

    func testState06CurrentWeightOnly() throws {
        // Current weight present (starting falls back to current, as commit() does),
        // no goal: the hero shows the number and prompts for a goal.
        let app = launchSeeded(startingNowProfile(["--gaurava-seed-starting", "92.4", "--gaurava-seed-current", "92.4"]))
        XCTAssertTrue(app.staticTexts["92.4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["summaryHeroSetGoal"].exists)
        XCTAssertTrue(app.buttons["summaryLogFirstInjection"].exists)
        // Same run checks the Jabs empty layout (ID off, zero injections).
        gotoJabs(app)
        XCTAssertTrue(app.buttons["jabsLogFirstInjection"].exists)
        XCTAssertFalse(element(app, "provisionalInjectionCard").exists)
        XCTAssertFalse(element(app, "jabs-total-count").exists)
    }

    func testState07CurrentWeightPlusInjectionDay() throws {
        let app = launchSeeded(startingNowProfile([
            "--gaurava-seed-starting", "92.4", "--gaurava-seed-current", "92.4", "--gaurava-seed-injection-day", "1"
        ]))
        XCTAssertTrue(app.staticTexts["92.4"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "provisionalInjectionCard").exists)
    }

    func testState08FullHero() throws {
        let app = launchSeeded(startingNowProfile([
            "--gaurava-seed-starting", "98", "--gaurava-seed-goal", "80", "--gaurava-seed-current", "92.4"
        ]))
        XCTAssertTrue(app.staticTexts["92.4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goal'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["summaryLogFirstInjection"].exists)
    }

    func testState09Richest() throws {
        let app = launchSeeded(startingNowProfile([
            "--gaurava-seed-starting", "98", "--gaurava-seed-goal", "80",
            "--gaurava-seed-current", "92.4", "--gaurava-seed-injection-day", "1"
        ]))
        XCTAssertTrue(app.staticTexts["92.4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goal'")).firstMatch.exists)
        XCTAssertTrue(element(app, "provisionalInjectionCard").exists)
    }
}
