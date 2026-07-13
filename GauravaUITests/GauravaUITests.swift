import XCTest

@MainActor
final class GauravaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMainTabsAppear() throws {
        let app = XCUIApplication()
        // Reset so this is hermetic: a clean install otherwise shows the
        // first-run setup screen instead of the tab shell.
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 5))
        XCTAssertTrue(app.gauravaTab(.jabs).exists)
        XCTAssertTrue(app.gauravaTab(.results).exists)
        XCTAssertTrue(app.gauravaTab(.log).exists)
        XCTAssertTrue(app.gauravaTab(.care).exists)
    }

    func testSummaryDailyLogActionOpensDailyNoteSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["Daily Log"].waitForExistence(timeout: 5))
        app.buttons["Daily Log"].tap()

        XCTAssertTrue(app.navigationBars["Daily Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily note"].exists)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)

        let noteText = "Summary note visible in Log"
        let editor = app.descendants(matching: .any)["daily-log-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(noteText)

        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 10))
        app.gauravaTab(.log).tap()
        XCTAssertTrue(app.staticTexts[noteText].waitForExistence(timeout: 10))
    }

    func testLogAndSummaryNotesAppendWithoutOverwrite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 10))
        app.gauravaTab(.log).tap()

        let logNote = "Log tab note"
        let noteEntry = app.buttons["Add a note"].firstMatch
        XCTAssertTrue(noteEntry.waitForExistence(timeout: 10))
        noteEntry.tap()

        let logEditor = app.descendants(matching: .any)["Anything the chips don't cover…"]
        XCTAssertTrue(logEditor.waitForExistence(timeout: 5))
        logEditor.tap()
        app.typeText(logNote)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts[logNote].waitForExistence(timeout: 10))

        XCTAssertTrue(app.gauravaTab(.summary).waitForExistence(timeout: 10))
        app.gauravaTab(.summary).tap()
        XCTAssertTrue(app.buttons["Daily Log"].waitForExistence(timeout: 5))
        app.buttons["Daily Log"].tap()

        XCTAssertTrue(app.navigationBars["Daily Note"].waitForExistence(timeout: 5))
        let summaryNote = "Summary daily note"
        XCTAssertTrue(app.descendants(matching: .any)["daily-log-text-editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(summaryNote)
        app.buttons["Save"].tap()

        app.gauravaTab(.log).tap()
        XCTAssertTrue(app.staticTexts["\(logNote)\n\n\(summaryNote)"].waitForExistence(timeout: 10))
    }

    func testOwnerSeedImportPersistsAcrossRelaunch() throws {
        let seedURL = URL(fileURLWithPath: Self.privateOwnerSeedPath)
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw XCTSkip("Private owner seed JSON is not available on this machine.")
        }

        let seedData = try Data(contentsOf: seedURL)
        let importingApp = XCUIApplication()
        importingApp.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            seedURL.path
        ]
        importingApp.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = seedData.base64EncodedString()
        importingApp.launch()

        assertSeededDataAppears(in: importingApp)
        importingApp.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launch()
        assertSeededDataAppears(in: relaunchedApp)
    }

    func testSeededResultsShowsReferenceChartControls() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(app.gauravaTab(.results).waitForExistence(timeout: 10))
        app.gauravaTab(.results).tap()

        XCTAssertTrue(app.descendants(matching: .any)["results-weight-entry-count"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["results-total-change"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["results-reference-chart"].exists)

        let doseLegend = app.descendants(matching: .any)["results-dose-color-legend"]
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5), "Results scroll view never appeared")
        var scrollAttempts = 0
        while !doseLegend.exists && scrollAttempts < 4 {
            scrollView.swipeUp()
            _ = doseLegend.waitForExistence(timeout: 2)
            scrollAttempts += 1
        }

        XCTAssertTrue(doseLegend.exists)
        XCTAssertTrue(app.descendants(matching: .any)["results-dose-labels-toggle"].exists)
    }

    func testLogOneGlassMoodQuestionCanChangeSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 10))
        app.gauravaTab(.log).tap()

        let goodMood = app.buttons["mood-face-good"]
        XCTAssertTrue(goodMood.waitForExistence(timeout: 10))
        goodMood.tap()

        let confirmation = app.buttons["mood-confirmation-pill"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        let reopenedGood = app.buttons["mood-face-good"]
        XCTAssertTrue(reopenedGood.waitForExistence(timeout: 5))
        XCTAssertFalse(reopenedGood.isSelected)

        let greatMood = app.buttons["mood-face-great"]
        XCTAssertTrue(greatMood.waitForExistence(timeout: 5))
        XCTAssertTrue(greatMood.isHittable)
        greatMood.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mood-confirmation-pill"].waitForExistence(timeout: 5))
    }

    func testLogMoodUnselectRemovesRecentMoodChipImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 10))
        app.gauravaTab(.log).tap()

        let sideEffects = app.buttons["Anything else? Side effects"].firstMatch
        XCTAssertTrue(sideEffects.waitForExistence(timeout: 10))
        sideEffects.tap()

        let picker = app.descendants(matching: .any)["side-effect-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let nausea = picker.buttons["side-effect-chip-nausea"].firstMatch
        XCTAssertTrue(nausea.waitForExistence(timeout: 5))
        nausea.tap()
        app.buttons["Done"].firstMatch.tap()

        let okayMood = app.buttons["mood-face-okay"]
        XCTAssertTrue(okayMood.waitForExistence(timeout: 10))
        okayMood.tap()

        let recentOkay = app.descendants(matching: .any)["log-recent-mood-okay"]
        XCTAssertTrue(recentOkay.waitForExistence(timeout: 5))

        let confirmation = app.buttons["mood-confirmation-pill"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()

        XCTAssertTrue(app.buttons["mood-face-okay"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mood-face-okay"].isSelected)
        XCTAssertFalse(recentOkay.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Nausea"].exists)
    }

    func testLogSideEffectEntryUsesSheetInsteadOfInlinePicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.log).waitForExistence(timeout: 10))
        app.gauravaTab(.log).tap()

        let sideEffects = app.buttons["Anything else? Side effects"].firstMatch
        XCTAssertTrue(sideEffects.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["side-effect-chip-nausea"].exists)

        sideEffects.tap()
        let picker = app.descendants(matching: .any)["side-effect-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        let nausea = picker.buttons["side-effect-chip-nausea"].firstMatch
        XCTAssertTrue(nausea.waitForExistence(timeout: 5))
        nausea.tap()

        let severe = picker.buttons["severity-choice-nausea-severe"].firstMatch
        XCTAssertTrue(severe.waitForExistence(timeout: 5))
        severe.tap()

        app.buttons["Done"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Nausea · Severe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["from Lock Screen"].exists)
    }

    func testSeededCareShareJourneyComposerShowsExportControls() throws {
        let app = try launchSeededApp()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 10))
        app.gauravaTab(.care).tap()

        let entry = app.descendants(matching: .any)["share-journey-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        XCTAssertTrue(app.navigationBars["Share Journey"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["share-card-preview"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["share-card-template-journey"].exists)
        XCTAssertTrue(app.buttons["share-card-template-story"].exists)
        XCTAssertTrue(app.buttons["share-card-template-milestone"].exists)

        let dataButton = app.buttons["share-card-template-dataSheet"]
        if !dataButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(dataButton.waitForExistence(timeout: 5))

        let milestoneButton = app.buttons["share-card-template-milestone"]
        XCTAssertTrue(milestoneButton.waitForExistence(timeout: 5))
        if !milestoneButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(milestoneButton.isHittable)
        milestoneButton.tap()

        let storyButton = app.buttons["share-card-template-story"]
        XCTAssertTrue(storyButton.waitForExistence(timeout: 5))
        if !storyButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(storyButton.isHittable)
        storyButton.tap()

        let saveButton = app.buttons["share-card-save-button"]
        if !saveButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["share-card-share-button"].exists)
    }

    func testCarePrivacyDataSafetyAndAboutSurfacesOpen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gaurava-reset-local-data-for-testing"]
        app.launch()

        XCTAssertTrue(app.gauravaTab(.care).waitForExistence(timeout: 10))
        app.gauravaTab(.care).tap()

        openCareSurface("care-privacy-statement-row", titled: "Privacy Statement", in: app)
        openCareSurface("care-data-controls-row", titled: "Data Controls", in: app)
        openCareSurface("care-medical-safety-row", titled: "Medical Safety", in: app)
        openCareSurface("care-about-row", titled: "About Gaurava", in: app)
    }

    private func assertSeededDataAppears(in app: XCUIApplication) {
        XCTAssertTrue(app.gauravaTab(.results).waitForExistence(timeout: 10))
        app.gauravaTab(.results).tap()

        let weightCount = app.descendants(matching: .any)["results-weight-entry-count"]
        XCTAssertTrue(weightCount.waitForExistence(timeout: 20))
        // Seed-agnostic: the seeded profile always has weight entries; assert a
        // non-zero count rendered instead of a hardcoded number ("15") that
        // re-breaks whenever the owner seed is refreshed.
        XCTAssertNotNil(
            weightCount.label.range(of: #"[1-9]"#, options: .regularExpression),
            "Expected a non-zero weight-entry count, got '\(weightCount.label)'"
        )

        app.gauravaTab(.jabs).tap()
        let jabCount = app.descendants(matching: .any)["jabs-total-count"]
        XCTAssertTrue(jabCount.waitForExistence(timeout: 10))
        // Seed-agnostic: assert a non-zero injection total rather than a specific
        // count ("22") tied to one seed snapshot.
        XCTAssertNotNil(
            jabCount.label.range(of: #"[1-9]"#, options: .regularExpression),
            "Expected a non-zero injection total, got '\(jabCount.label)'"
        )

        app.gauravaTab(.log).tap()
        XCTAssertTrue(app.descendants(matching: .any)["log-capture-card"].waitForExistence(timeout: 10))
    }

    private func launchSeededApp() throws -> XCUIApplication {
        let seedURL = URL(fileURLWithPath: Self.privateOwnerSeedPath)
        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw XCTSkip("Private owner seed JSON is not available on this machine.")
        }

        let seedData = try Data(contentsOf: seedURL)
        let app = XCUIApplication()
        app.launchArguments = [
            "--gaurava-reset-local-data-for-testing",
            "--gaurava-owner-seed-import",
            seedURL.path
        ]
        app.launchEnvironment["GAURAVA_OWNER_SEED_JSON_B64"] = seedData.base64EncodedString()
        app.launch()
        return app
    }

    private func openCareSurface(_ identifier: String, titled title: String, in app: XCUIApplication) {
        let row = app.descendants(matching: .any)[identifier]
        // Scroll until the row is actually hittable. The Care screen grows as rows
        // are added (e.g. the Language row in Preferences), so a fixed swipe count
        // is brittle — loop on hittability instead.
        var attempts = 0
        while !row.isHittable && attempts < 12 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(row.isHittable, "\(identifier) was not hittable")
        row.tap()

        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Missing \(title) sheet")
        app.buttons["Done"].tap()
    }

    private static let privateOwnerSeedPath = PrivateOwnerSeed.path
}
