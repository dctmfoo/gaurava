import XCTest

@MainActor
final class SemaglutideVerificationScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureTirzepatideVerificationSurfaces() throws {
        try captureSeededSurfaces(.tirzepatide)
    }

    func testCaptureSemaglutideVerificationSurfaces() throws {
        try captureSeededSurfaces(.semaglutide)
    }

    func testCaptureMixedVerificationSurfaces() throws {
        try captureSeededSurfaces(.mixed)
    }

    func testCaptureSemaglutideStarterRoundTripAndExports() throws {
        let app = launchStarterSeed()
        waitForSeededSummary(in: app)

        app.gauravaTab(.jabs).tap()
        settle()
        attach(app, "starter-semaglutide-01-jabs-025-timeline")

        let starterDoseRow = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "0.25 mg")
        ).firstMatch
        XCTAssertTrue(starterDoseRow.waitForExistence(timeout: 10), "Expected the starter 0.25 mg dose in the Jabs timeline.")
        starterDoseRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["edit-injection-sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["0.25 mg"].waitForExistence(timeout: 5))
        attach(app, "starter-semaglutide-02-edit-025-selected")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["0.25 mg"].waitForExistence(timeout: 5), "0.25 mg should still render after saving the edit sheet.")
        attach(app, "starter-semaglutide-03-after-save-025")

        app.gauravaTab(.care).tap()
        openShareComposer(in: app, prefix: "starter-semaglutide")
        dismissSheetIfNeeded(in: app)

        app.gauravaTab(.care).tap()
        openClinicianExport(in: app, prefix: "starter-semaglutide")
    }

    private func captureSeededSurfaces(_ variant: MarketingSeedVariant) throws {
        let prefix = variant.rawValue
        let app = launchMarketingSeed(variant)
        waitForSeededSummary(in: app)
        settle()
        attach(app, "\(prefix)-01-summary-current-dose")

        app.gauravaTab(.jabs).tap()
        settle()
        attach(app, "\(prefix)-02-jabs-last-dose-and-timeline")

        app.gauravaTab(.results).tap()
        settle()
        attach(app, "\(prefix)-03-results-overview")
        app.swipeUp()
        app.swipeUp()
        settle()
        attach(app, "\(prefix)-04-results-dose-chart")

        app.gauravaTab(.log).tap()
        settle()
        attach(app, "\(prefix)-05-log-dose-chip")
        app.swipeUp()
        settle()
        attach(app, "\(prefix)-06-log-recent-dose-colors")

        app.gauravaTab(.care).tap()
        settle()
        attach(app, "\(prefix)-07-care-drug-row")
        openShareComposer(in: app, prefix: prefix)
        dismissSheetIfNeeded(in: app)
        openPlannedDoseSheet(in: app, prefix: prefix)

        app.gauravaTab(.care).tap()
        openClinicianExport(in: app, prefix: prefix)
    }

    private func launchMarketingSeed(_ variant: MarketingSeedVariant) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            "--seed-medication",
            variant.rawValue
        ]
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = MarketingSeed.base64JSON(variant: variant)
        app.launch()
        return app
    }

    private func launchStarterSeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            "--seed-medication",
            MarketingSeedVariant.semaglutide.rawValue
        ]
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = StarterSemaglutideSeed.base64JSON()
        app.launch()
        return app
    }

    private func waitForSeededSummary(in app: XCUIApplication) {
        let hero = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "84")
        ).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 40), "Seeded Summary hero never appeared.")
        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 10))
    }

    private func openPlannedDoseSheet(in app: XCUIApplication, prefix: String) {
        let row = app.descendants(matching: .any)["settings-planned-dose-row"]
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["planned-dose-editor-sheet"].waitForExistence(timeout: 5))
        attach(app, "\(prefix)-08-settings-planned-dose-picker")
        app.buttons["Cancel"].tap()
        settle(0.8)
    }

    private func openShareComposer(in app: XCUIApplication, prefix: String) {
        let entry = app.descendants(matching: .any)["share-journey-entry"]
        scrollTo(entry, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()

        let preview = app.images["share-card-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        settle(1.8)
        attach(app, "\(prefix)-09-share-composer")

        if app.descendants(matching: .any)["share-card-template-dataSheet"].exists {
            app.descendants(matching: .any)["share-card-template-dataSheet"].tap()
            settle(1.4)
        }
        attach(preview, "\(prefix)-10-share-card-data-sheet")
    }

    private func openClinicianExport(in app: XCUIApplication, prefix: String) {
        let row = app.descendants(matching: .any)["care-clinician-export-row"]
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        let sheet = app.descendants(matching: .any)["clinician-export-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        settle(1.2)
        attach(app, "\(prefix)-11-clinician-export-pdf-preview")
    }

    private func dismissSheetIfNeeded(in app: XCUIApplication) {
        if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
            settle(0.8)
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func attach(_ element: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.exists || !element.isHittable {
            app.swipeUp()
            settle(0.35)
        }
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

private enum StarterSemaglutideSeed {
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
        let startDate = at(-24, hour: 7, minute: 30)
        let jabDate = at(-3, hour: 9)
        let preferredWeekday = calendar.component(.weekday, from: jabDate)

        return [
            "meta": [
                "sourceProduct": "semaglutide-verification-seed",
                "targetProduct": "gaurava",
                "subjectEmail": "gaurava.user@icloud.com",
                "exportedAt": stamp(Date()),
                "version": "starter-semaglutide-1"
            ],
            "account": ["email": "gaurava.user@icloud.com"],
            "data": [
                "profiles": [[
                    "id": "verification-starter-profile",
                    "age": 41,
                    "gender": "",
                    "height_cm": "178",
                    "starting_weight_kg": "98.0",
                    "goal_weight_kg": "80.0",
                    "treatment_start_date": stamp(startDate),
                    "medication": "semaglutide",
                    "planned_dose_mg": "0.25",
                    "preferred_injection_day": preferredWeekday,
                    "reminder_days_before": 1,
                    "created_at": stamp(startDate),
                    "updated_at": stamp(Date())
                ]],
                "userPreferences": [[
                    "id": "verification-starter-pref",
                    "weight_unit": "kg",
                    "height_unit": "cm",
                    "date_format": "DD/MM/YYYY",
                    "week_starts_on": 1,
                    "theme": "light"
                ]],
                "weightEntries": [
                    weight("verification-weight-0", -24, "98.0", "Treatment start"),
                    weight("verification-weight-1", -10, "93.2", nil),
                    weight("verification-weight-2", -1, "84.3", nil)
                ],
                "injections": [[
                    "id": "verification-jab-025",
                    "dose_mg": "0.25",
                    "injection_site": "Abdomen - Left",
                    "injection_date": stamp(jabDate),
                    "time_zone_identifier": TimeZone.current.identifier,
                    "notes": "Starter semaglutide verification dose."
                ]],
                "sideEffects": [[
                    "id": "verification-side-effect-nausea",
                    "log_date": stamp(at(-2, hour: 12)),
                    "symptom": "nausea",
                    "severity": "mild",
                    "source": "app",
                    "time_zone_identifier": TimeZone.current.identifier,
                    "client_mutation_id": "verification-se-nausea"
                ]],
                "checkIns": [[
                    "id": "verification-check-in",
                    "log_date": stamp(at(-2, hour: 12)),
                    "mood_valence": "okay",
                    "all_clear": false,
                    "note": "Mild nausea, resolved after lunch.",
                    "source": "app",
                    "time_zone_identifier": TimeZone.current.identifier,
                    "client_mutation_id": "verification-ci"
                ]]
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
}
