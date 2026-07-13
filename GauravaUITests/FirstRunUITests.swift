import XCTest

/// First-run onboarding (baseline split + mandatory hard gate, see
/// docs/onboarding-baseline-split-plan.html v1.3). Production fresh installs see the
/// value-only Welcome first; setup-focused tests use `--gaurava-show-first-run` to land
/// directly on the Status question, and `--gaurava-first-run-branch <token>` to
/// deep-link into a branch's first step.
///
/// The baseline is MANDATORY: every branch must supply current weight, starting weight,
/// and goal weight (and the active branch a treatment-start date) before Continue
/// advances, and there is no "Set up later" exit. Tests walk the gate using each
/// required field's one-tap satisfier — the treatment-start chip, "Same as today", and
/// the seeded goal ruler.
@MainActor
final class FirstRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launchers

    /// Lands on the Status question (the splash Welcome is skipped).
    private func launchStatus() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run"
        ]
        app.launch()
        return app
    }

    /// Lands on the production Welcome (value + trust, no status control).
    private func launchWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run",
            "--gaurava-show-first-run-welcome"
        ]
        app.launch()
        return app
    }

    /// Deep-links into the "Just starting" branch (status pre-set), landing on the
    /// medicine step so injection-day coverage doesn't tap through Welcome + Status.
    private func launchStartingBranch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run",
            "--gaurava-first-run-branch", "startingNow"
        ]
        app.launch()
        return app
    }

    /// Deep-links into the "Yes, I've started" branch, landing on latest-dose
    /// setup so active-branch tests can advance without the Welcome + Status taps.
    private func launchActiveBranch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run",
            "--gaurava-first-run-branch", "active"
        ]
        app.launch()
        return app
    }

    // MARK: - Flow helpers

    /// Tap the primary Continue button (advance one step), swiping up first if the
    /// floating action bar is below the fold.
    private func tapContinue(_ app: XCUIApplication) {
        let cont = app.buttons["firstRunContinue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        if !cont.isHittable { app.swipeUp() }
        cont.tap()
    }

    private func typeWeight(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field: \(id)")
        field.tap()
        field.typeText(text)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
    }

    private func typeAndDismiss(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
    }

    /// Active branch only: satisfy the mandatory treatment-start step with the "Today"
    /// quick chip, then advance off it.
    private func provideTreatmentStart(_ app: XCUIApplication) {
        let today = app.buttons["firstRunTreatmentStartPreset0"]
        XCTAssertTrue(today.waitForExistence(timeout: 5), "treatment-start chip missing")
        if !today.isHittable { app.swipeUp() }
        today.tap()
        tapContinue(app) // treatment start → Apple Health
    }

    /// Walk the mandatory weight baseline from the Apple Health step to the close
    /// screen, using the one-tap satisfiers: pass Apple Health (exempt) with Continue,
    /// type the current weight, copy it into starting via "Same as today", and accept
    /// the seeded goal ruler. Leaves the app on the close screen.
    private func fillMandatoryWeights(_ app: XCUIApplication, current: String) {
        // Apple Health is its own exempt screen on a HealthKit-capable simulator.
        if app.buttons["firstRunHealthConnect"].waitForExistence(timeout: 5) {
            tapContinue(app) // Apple Health → current weight
        }
        typeWeight(app, "firstRunCurrentWeight", current)
        tapContinue(app) // current → starting
        let sameAsToday = app.buttons["firstRunStartingSameAsToday"]
        XCTAssertTrue(sameAsToday.waitForExistence(timeout: 5), "same-as-today chip missing")
        if !sameAsToday.isHittable { app.swipeUp() }
        sameAsToday.tap()
        tapContinue(app) // starting → goal (seeds the ruler so Continue is satisfied)
        tapContinue(app) // goal (seeded) → close
    }

    private func openGauravaFromClose(_ app: XCUIApplication) {
        let close = app.descendants(matching: .any)["firstRunClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What happens next"].waitForExistence(timeout: 2))
        app.buttons["firstRunContinue"].tap()
    }

    // MARK: - Welcome + the single Status question

    func testWelcomeShowsValueThenLeadsToStatusQuestion() throws {
        let app = launchWelcome()

        XCTAssertTrue(app.buttons["firstRunBegin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["firstRunWelcomeHeadline"].exists)
        // The status question is NOT on Welcome anymore — that was the duplication bug.
        XCTAssertFalse(app.buttons["firstRunTreatmentStatus-active"].exists)
        XCTAssertFalse(app.textFields["Current weight (kg)"].exists)

        app.buttons["firstRunBegin"].tap()

        // The Status step: the question, asked exactly once. The hard gate keeps
        // Continue disabled until a status is chosen, and there is no skip button.
        XCTAssertTrue(app.staticTexts["Have you started GLP-1 yet?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["firstRunTreatmentStatus-startingNow"].exists)
        XCTAssertTrue(app.buttons["firstRunTreatmentStatus-active"].exists)
        XCTAssertFalse(app.buttons["firstRunTreatmentStatus-paused"].exists)
        XCTAssertFalse(app.buttons["firstRunContinue"].isEnabled)
        XCTAssertFalse(app.buttons["firstRunBegin"].exists)
    }

    func testStatusSelectionRoutesToActiveBranch() throws {
        let app = launchStatus()

        let active = app.buttons["firstRunTreatmentStatus-active"]
        XCTAssertTrue(active.waitForExistence(timeout: 5))
        active.tap()
        app.buttons["firstRunContinue"].tap()

        // Active is anchor-first: the most-recent-dose screen leads the branch.
        XCTAssertTrue(app.staticTexts["Latest dose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["firstRunMostRecentDosePreset0"].exists)
    }

    func testFirstRunShowsStatusQuestionOnFreshInstall() throws {
        let app = launchStatus()

        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Have you started GLP-1 yet?"].exists)
        XCTAssertFalse(app.buttons["firstRunContinue"].isEnabled)
        // The tab shell is gated behind onboarding.
        XCTAssertFalse(app.gauravaTab(.summary).exists)
    }

    /// Completing the mandatory flow lands in the tab shell, and first-run completion
    /// persists across a relaunch (the hard gate replaces the old skip path).
    func testCompletingFirstRunEntersTabShellAndDoesNotReturn() throws {
        let app = launchStatus()

        app.buttons["firstRunTreatmentStatus-startingNow"].tap()
        tapContinue(app) // status → medicine
        tapContinue(app) // medicine → weekly-plan
        tapContinue(app) // weekly-plan → reminders
        tapContinue(app) // reminders → Apple Health
        fillMandatoryWeights(app, current: "88")
        openGauravaFromClose(app)

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.gauravaTab(.summary).waitForExistence(timeout: 5))
    }

    // MARK: - Just-starting branch

    func testInjectionDayToggleRevealsPickerAndContinuesToTabShell() throws {
        let app = launchStartingBranch()

        // Branch lands on the medicine step; advance to the weekly-plan step.
        tapContinue(app) // medicine → weekly-plan

        let mondayChip = app.buttons["firstRunInjectionDay-1"]
        XCTAssertTrue(mondayChip.waitForExistence(timeout: 5))
        if !mondayChip.isHittable { app.swipeUp() }
        mondayChip.tap()

        // Tapping a weekday enables the plan and shows the weekly-plan note.
        XCTAssertTrue(app.revealFirstRunInjectionDayPicker().exists)

        tapContinue(app) // weekly-plan → reminders
        tapContinue(app) // reminders → Apple Health
        fillMandatoryWeights(app, current: "85")
        openGauravaFromClose(app)

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))
    }

    func testContinueWithCurrentWeightLightsUpJourney() throws {
        let app = launchStatus()

        // Choose the visible "before first dose" path, then leave medicine, weekly
        // plan, and reminders blank until the mandatory weight steps.
        app.buttons["firstRunTreatmentStatus-startingNow"].tap()
        tapContinue(app) // status → medicine
        tapContinue(app) // medicine → weekly-plan
        tapContinue(app) // weekly-plan → reminders
        tapContinue(app) // reminders → Apple Health
        fillMandatoryWeights(app, current: "90")
        openGauravaFromClose(app)

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))
        // The entered current weight surfaces on the Journey hero card.
        XCTAssertTrue(app.staticTexts["90.0"].waitForExistence(timeout: 5))
    }

    /// After the split, Apple Health is its own exempt screen, separate from the manual
    /// current-weight field that follows it. HealthKit is available on the simulator, so
    /// the opt-in renders; we assert it exists but never tap it — that would raise the
    /// real system permission dialog, which a UI test cannot drive.
    func testWeightStepOffersAppleHealthImport() throws {
        let app = launchStartingBranch()

        tapContinue(app) // medicine → weekly-plan
        tapContinue(app) // weekly-plan → reminders
        tapContinue(app) // reminders → Apple Health

        // The Apple Health screen carries the import affordance; the manual
        // current-weight field is the NEXT screen, not this one.
        XCTAssertTrue(app.buttons["firstRunHealthConnect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["firstRunCurrentWeight"].exists)

        tapContinue(app) // Apple Health → current weight
        XCTAssertTrue(app.textFields["firstRunCurrentWeight"].waitForExistence(timeout: 5))
    }

    // MARK: - Active branch

    func testBaselineKeyboardHidesOnboardingActionsUntilDone() throws {
        let app = launchActiveBranch()

        // Active branch: latest dose → medicine → reminders → treatment start → health → current.
        tapContinue(app) // latest dose → medicine
        tapContinue(app) // medicine → reminders
        tapContinue(app) // reminders → treatment start
        provideTreatmentStart(app) // treatment start → Apple Health
        if app.buttons["firstRunHealthConnect"].waitForExistence(timeout: 5) {
            tapContinue(app) // Apple Health → current weight
        }

        let currentWeight = app.textFields["firstRunCurrentWeight"]
        XCTAssertTrue(currentWeight.waitForExistence(timeout: 5))
        currentWeight.tap()

        // While the keyboard is up, the floating action bar is hidden (only the
        // keyboard "Done" advances), then it returns once the field is dismissed.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["firstRunContinue"].exists)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 5))

        // Finish the mandatory baseline and land in the tab shell.
        currentWeight.tap()
        currentWeight.typeText("91")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        tapContinue(app) // current → starting
        let sameAsToday = app.buttons["firstRunStartingSameAsToday"]
        XCTAssertTrue(sameAsToday.waitForExistence(timeout: 5))
        sameAsToday.tap()
        tapContinue(app) // starting → goal
        tapContinue(app) // goal → close
        openGauravaFromClose(app)

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))
    }

    func testActiveMedicineSelectionRevealsDoseAndCanReturnToBlank() throws {
        let app = launchActiveBranch()

        // Active branch: latest dose → medicine/current-dose.
        tapContinue(app)
        XCTAssertTrue(app.staticTexts["Medicine"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["firstRunDose-10"].exists)

        let tirzepatide = app.buttons["firstRunMedication-tirzepatide"]
        XCTAssertTrue(tirzepatide.waitForExistence(timeout: 5))
        tirzepatide.tap()

        let tenMg = app.buttons["firstRunDose-10"]
        XCTAssertTrue(tenMg.waitForExistence(timeout: 5))
        tenMg.tap()

        // Tapping the selected medicine again returns the optional record to blank.
        tirzepatide.tap()
        XCTAssertFalse(app.buttons["firstRunDose-10"].exists)

        // Re-selecting still reveals the same dose ladder and continues normally.
        tirzepatide.tap()
        XCTAssertTrue(app.buttons["firstRunDose-10"].waitForExistence(timeout: 5))
        app.buttons["firstRunDose-10"].tap()
        tapContinue(app) // medicine → reminders
        tapContinue(app) // reminders → treatment start

        // After the split, the active branch reaches the treatment-start screen here
        // (the old combined "Baseline" screen is gone).
        XCTAssertTrue(app.staticTexts["When did you start?"].waitForExistence(timeout: 5))
    }

    /// Regression for the cross-tab contradiction the bucketed revamp fixed
    /// (docs/post-onboarding-bucketed-revamp-plan.html §Build sequencing #1): an
    /// active user who confirmed their most recent dose in onboarding — but has not
    /// logged a jab — must see the LIVE next-injection schedule on Summary, never
    /// "Log first injection", and Jabs must show the same countdown.
    func testActiveConfirmedDoseShowsLiveScheduleOnSummaryNotLogFirst() throws {
        let app = launchActiveBranch()

        // Latest-dose step: confirm "yesterday" (the "this is my latest dose"
        // toggle defaults on), anchoring the schedule with no logged injection. This
        // test intentionally does NOT pick a dose on the Medicine screen, so onboarding
        // stays anchor-only and records no jab; the dose-known path that DOES record a
        // jab is covered by testActiveConfirmedDoseWithKnownDoseRecordsJabInHistory.
        let yesterday = app.buttons["firstRunMostRecentDosePreset1"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 8))
        yesterday.tap()
        tapContinue(app) // latest dose → medicine
        tapContinue(app) // medicine → reminders
        tapContinue(app) // reminders → treatment start
        provideTreatmentStart(app) // treatment start → Apple Health
        fillMandatoryWeights(app, current: "91") // health → current → starting → goal → close
        openGauravaFromClose(app) // close → tab shell
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 8))

        // Summary honors the confirmed schedule: the live panel, not the CTA.
        XCTAssertTrue(app.staticTexts["Next injection"].waitForExistence(timeout: 5),
                      "Summary must show the live next-injection schedule for a confirmed dose")
        XCTAssertFalse(app.buttons["summaryLogFirstInjection"].exists,
                       "Summary must NOT say 'Log first injection' while a countdown is running")

        // Jabs shows the same countdown — the two tabs agree. NextDueCard combines
        // its children for accessibility, so assert the card by identifier rather
        // than its inner "Next injection" text.
        app.gauravaTab(.jabs).tap()
        XCTAssertTrue(app.descendants(matching: .any)["jabsNextDueCard"].waitForExistence(timeout: 5),
                      "Jabs must show the same next-injection countdown")
        XCTAssertFalse(app.buttons["jabsLogFirstInjection"].exists)
    }

    /// Companion to the test above: when the active user confirms their latest dose
    /// AND a dose is known (picked on the Medicine screen), onboarding records it as a
    /// real jab, so the Jabs history is populated rather than showing the "Log each jab
    /// to build your history" prompt. The schedule is unchanged — the engine keys off
    /// `max(newestInjection, anchor)`, both the same date — so the countdown still
    /// shows. A known dose is the gate; the no-dose test above stays anchor-only.
    func testActiveConfirmedDoseWithKnownDoseRecordsJabInHistory() throws {
        let app = launchActiveBranch()

        // Latest-dose step: confirm "yesterday" (latest-dose toggle defaults on).
        let yesterday = app.buttons["firstRunMostRecentDosePreset1"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 8))
        yesterday.tap()
        tapContinue(app) // latest dose → medicine

        // Medicine step: pick a medication + dose so the jab can be recorded honestly
        // (a dose is required to materialize it).
        let tirzepatide = app.buttons["firstRunMedication-tirzepatide"]
        XCTAssertTrue(tirzepatide.waitForExistence(timeout: 5))
        tirzepatide.tap()
        let tenMg = app.buttons["firstRunDose-10"]
        XCTAssertTrue(tenMg.waitForExistence(timeout: 5))
        tenMg.tap()
        tapContinue(app) // medicine → reminders
        tapContinue(app) // reminders → treatment start
        provideTreatmentStart(app) // treatment start → Apple Health
        fillMandatoryWeights(app, current: "91") // health → current → starting → goal → close
        openGauravaFromClose(app) // close → tab shell

        app.gauravaTab(.jabs).tap()
        // The countdown still shows (the anchor equals the materialized jab's date)…
        XCTAssertTrue(app.descendants(matching: .any)["jabsNextDueCard"].waitForExistence(timeout: 8),
                      "Jabs must still show the next-injection countdown")
        // …and the history is now populated: the stat strip renders only with ≥1 jab,
        // and the empty "build your history" prompt is gone.
        XCTAssertTrue(app.descendants(matching: .any)["jabs-total-count"].waitForExistence(timeout: 5),
                      "A confirmed last dose with a known dose must record a jab (stat strip shows)")
        XCTAssertFalse(app.buttons["jabsLogJab"].exists,
                       "The 'Log each jab to build your history' prompt must not show once the last dose is recorded")
        XCTAssertFalse(app.buttons["jabsAddPastJabs"].exists)
    }

    // MARK: - Post-onboarding goals editor (reachable for legacy/partial data)

    /// The empty-Summary "set your numbers" shortcut. A fresh install now always
    /// carries a baseline, so this state is reached the way legacy/imported data
    /// reaches it — first-run already complete, no data — via a plain reset.
    func testSetYourNumbersFromEmptyStateLightsUpJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 8))

        // The empty Journey offers a one-tap shortcut to set goals.
        let prompt = app.buttons["summarySetNumbers"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()

        // The same goals editor Care uses. No profile yet, so both fields start empty.
        typeAndDismiss(app, app.textFields["Starting weight kg"], "98")
        typeAndDismiss(app, app.textFields["Goal weight kg"], "80")
        app.buttons["Save"].tap()

        // The hero now shows the goal framing (one "Start … · Goal …" reference
        // line since the hero redesign) and the prompt is gone.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goal'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["summarySetNumbers"].exists)
    }

    /// The hero "set goal" prompt when a current weight exists but no goal does. Under
    /// the mandatory baseline this is a legacy/partial-data state, seeded directly.
    func testHeroSetGoalPromptResolvesProgress() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-seed-profile", "--gaurava-seed-status", "startingNow",
            "--gaurava-seed-starting", "92.4", "--gaurava-seed-current", "92.4"
        ]
        app.launch()
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 8))

        let heroPrompt = app.buttons["summaryHeroSetGoal"]
        XCTAssertTrue(heroPrompt.waitForExistence(timeout: 5))
        heroPrompt.tap()

        // Starting weight is already set, so only set a goal.
        typeAndDismiss(app, app.textFields["Goal weight kg"], "80")
        app.buttons["Save"].tap()

        // Progress framing now renders (merged "Start … · Goal …" line) and the
        // prompt is gone.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goal'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["summaryHeroSetGoal"].exists)
    }
}
