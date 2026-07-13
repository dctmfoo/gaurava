import XCTest

@MainActor
final class MedicationSelectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsMedicationSwitchWithoutProfileUsesSemaglutideDoseLadder() throws {
        let app = launchCleanTabShell()

        app.gauravaTab(.care).tap()
        switchMedicationInSettings(to: "semaglutide", in: app)
        assertPlannedDoseShowsSemaglutideLadder(in: app)
    }

    func testSettingsMedicationSwitchWithExistingProfileUsesSemaglutideDoseLadder() throws {
        // Create a profile (preferred injection day) through the "Just starting"
        // branch, then verify the Care medication switch in Settings.
        let app = launchStartingBranch()

        // Medicine step → weekly-plan step.
        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 5))
        app.buttons["firstRunContinue"].tap()

        let mondayChip = app.buttons["firstRunInjectionDay-1"]
        XCTAssertTrue(mondayChip.waitForExistence(timeout: 5))
        if !mondayChip.isHittable { app.swipeUp() }
        mondayChip.tap()

        // Weekly-plan → reminders → Apple Health → the mandatory weight baseline →
        // close, then open the app.
        app.buttons["firstRunContinue"].tap()   // weekly-plan → reminders
        let toHealth = app.buttons["firstRunContinue"]
        XCTAssertTrue(toHealth.waitForExistence(timeout: 5))
        if !toHealth.isHittable { app.swipeUp() }
        toHealth.tap()                          // reminders → Apple Health
        app.fillMandatoryOnboardingWeights(current: "90") // Apple Health → … → close
        XCTAssertTrue(app.descendants(matching: .any)["firstRunClose"].waitForExistence(timeout: 5))
        app.buttons["firstRunContinue"].tap()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 5))
        app.gauravaTab(.care).tap()
        switchMedicationInSettings(to: "semaglutide", in: app)
        assertPlannedDoseShowsSemaglutideLadder(in: app)
    }

    func testFirstJabSemaglutideChoicePersistsMedication() throws {
        let app = launchCleanTabShell()

        app.gauravaTab(.jabs).tap()
        let firstJab = app.descendants(matching: .any)["jabsLogFirstInjection"]
        XCTAssertTrue(firstJab.waitForExistence(timeout: 5))
        firstJab.tap()

        let semaglutide = app.buttons["first-jab-medication-semaglutide"]
        XCTAssertTrue(semaglutide.waitForExistence(timeout: 5))
        semaglutide.tap()
        XCTAssertTrue(app.buttons["0.25 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["7.2 mg"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 5))
        app.gauravaTab(.care).tap()
        let medicationRow = findElement("settings-medication-row", in: app)
        scrollTo(medicationRow, in: app)
        XCTAssertTrue(medicationRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Semaglutide"].waitForExistence(timeout: 5))
    }

    func testExistingTirzepatideHistorySwitchesToSemaglutideAndPreservesDoseTimeline() throws {
        let app = launchTirzepatideHistorySeed()

        app.gauravaTab(.jabs).tap()
        assertText("10 mg", appearsIn: app)
        assertText("5 mg", appearsIn: app)

        app.gauravaTab(.care).tap()
        switchMedicationInSettings(to: "semaglutide", in: app)
        assertPlannedDoseShowsSemaglutideLadder(in: app)

        app.gauravaTab(.jabs).tap()
        let addInjection = app.buttons["jabsAddInjection"]
        XCTAssertTrue(addInjection.waitForExistence(timeout: 5))
        addInjection.tap()

        XCTAssertTrue(app.descendants(matching: .any)["add-injection-sheet"].waitForExistence(timeout: 5))
        assertSemaglutideDoseButtons(in: app)
        app.buttons["1.7 mg"].tap()
        app.buttons["Save"].tap()

        assertText("1.7 mg", appearsIn: app, timeout: 10)
        assertText("10 mg", appearsIn: app)
        assertText("5 mg", appearsIn: app)
    }

    func testFirstJabSemaglutideOnePointSevenDoseRoundTripsFromCleanStore() throws {
        let app = launchCleanTabShell()

        app.gauravaTab(.jabs).tap()
        let firstJab = app.descendants(matching: .any)["jabsLogFirstInjection"]
        XCTAssertTrue(firstJab.waitForExistence(timeout: 5))
        firstJab.tap()

        let semaglutide = app.buttons["first-jab-medication-semaglutide"]
        XCTAssertTrue(semaglutide.waitForExistence(timeout: 5))
        semaglutide.tap()
        assertSemaglutideDoseButtons(in: app)
        app.buttons["1.7 mg"].tap()
        app.buttons["Save"].tap()

        assertText("1.7 mg", appearsIn: app, timeout: 10)

        app.gauravaTab(.summary).tap()
        XCTAssertTrue(app.staticTexts["Current dose"].waitForExistence(timeout: 5))
        assertText("1.7 mg", appearsIn: app)

        app.gauravaTab(.care).tap()
        let medicationRow = findElement("settings-medication-row", in: app)
        scrollTo(medicationRow, in: app)
        XCTAssertTrue(medicationRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Semaglutide"].waitForExistence(timeout: 5))
    }

    private func launchCleanTabShell() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))
        return app
    }

    private func launchStartingBranch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-show-first-run",
            "--gaurava-first-run-branch", "startingNow"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["firstRunContinue"].waitForExistence(timeout: 5))
        return app
    }

    private func launchTirzepatideHistorySeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            "--seed-medication",
            "tirzepatide"
        ]
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = MedicationLifecycleSeed.base64JSON()
        app.launch()
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 10))
        return app
    }

    private func switchMedicationInSettings(to rawValue: String, in app: XCUIApplication) {
        let medicationRow = findElement("settings-medication-row", in: app)
        scrollTo(medicationRow, in: app)
        XCTAssertTrue(medicationRow.waitForExistence(timeout: 5))
        medicationRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["medication-editor-sheet"].waitForExistence(timeout: 5))
        app.buttons["medication-option-\(rawValue)"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Semaglutide"].waitForExistence(timeout: 5))
    }

    private func assertPlannedDoseShowsSemaglutideLadder(in app: XCUIApplication) {
        let plannedDoseRow = findElement("settings-planned-dose-row", in: app)
        scrollTo(plannedDoseRow, in: app)
        XCTAssertTrue(plannedDoseRow.waitForExistence(timeout: 5))
        plannedDoseRow.tap()

        XCTAssertTrue(app.staticTexts["Planned Dose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["0.25 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["7.2 mg"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["15 mg"].exists)
        XCTAssertFalse(app.buttons["7.5 mg"].exists)
        app.buttons["Cancel"].tap()
    }

    private func assertSemaglutideDoseButtons(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["0.25 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1.7 mg"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["7.2 mg"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["15 mg"].exists)
        XCTAssertFalse(app.buttons["7.5 mg"].exists)
    }

    private func assertText(_ text: String, appearsIn app: XCUIApplication, timeout: TimeInterval = 5) {
        let element = app.staticTexts[text]
        if element.waitForExistence(timeout: timeout) {
            return
        }

        for _ in 0..<4 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return
            }
        }

        XCTFail("Expected to find text '\(text)'")
    }

    private func findElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}

private enum MedicationLifecycleSeed {
    static func base64JSON() -> String {
        let data = try! JSONSerialization.data(withJSONObject: envelope(), options: [])
        return data.base64EncodedString()
    }

    private static let calendar = Calendar.current

    private static func at(_ daysFromNow: Int, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func envelope() -> [String: Any] {
        let startDate = at(-28, hour: 8)
        let firstJabDate = at(-14, hour: 9)
        let secondJabDate = at(-7, hour: 9)
        let preferredWeekday = calendar.component(.weekday, from: secondJabDate)

        return [
            "meta": [
                "sourceProduct": "medication-lifecycle-ui-seed",
                "targetProduct": "gaurava",
                "subjectEmail": "gaurava.user@icloud.com",
                "exportedAt": stamp(Date()),
                "version": "tirzepatide-history-switch-1"
            ],
            "account": ["email": "gaurava.user@icloud.com"],
            "data": [
                "profiles": [[
                    "id": "lifecycle-tirzepatide-profile",
                    "age": 41,
                    "gender": "",
                    "height_cm": "178",
                    "starting_weight_kg": "98.0",
                    "goal_weight_kg": "80.0",
                    "treatment_start_date": stamp(startDate),
                    "medication": "tirzepatide",
                    "planned_dose_mg": "7.5",
                    "preferred_injection_day": preferredWeekday,
                    "reminder_days_before": 1,
                    "created_at": stamp(startDate),
                    "updated_at": stamp(Date())
                ]],
                "userPreferences": [[
                    "id": "lifecycle-tirzepatide-pref",
                    "weight_unit": "kg",
                    "height_unit": "cm",
                    "date_format": "DD/MM/YYYY",
                    "week_starts_on": 1,
                    "theme": "light"
                ]],
                "weightEntries": [
                    weight("lifecycle-weight-0", -28, "98.0", "Treatment start"),
                    weight("lifecycle-weight-1", -2, "90.8", nil)
                ],
                "injections": [
                    injection("lifecycle-jab-5", doseMg: "5", date: firstJabDate, site: "Abdomen - Left"),
                    injection("lifecycle-jab-10", doseMg: "10", date: secondJabDate, site: "Abdomen - Right")
                ],
                "sideEffects": [],
                "checkIns": []
            ]
        ]
    }

    private static func weight(_ id: String, _ day: Int, _ kg: String, _ notes: String?) -> [String: Any] {
        var entry: [String: Any] = [
            "id": id,
            "weight_kg": kg,
            "recorded_at": stamp(at(day, hour: 7, minute: 30)),
            "time_zone_identifier": TimeZone.current.identifier
        ]
        if let notes {
            entry["notes"] = notes
        }
        return entry
    }

    private static func injection(_ id: String, doseMg: String, date: Date, site: String) -> [String: Any] {
        [
            "id": id,
            "dose_mg": doseMg,
            "injection_site": site,
            "injection_date": stamp(date),
            "time_zone_identifier": TimeZone.current.identifier,
            "notes": "Lifecycle medication switch verification dose."
        ]
    }
}
